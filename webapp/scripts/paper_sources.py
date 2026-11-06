"""Local, untrusted paper extraction and metadata-only public PubMed discovery."""
import io
import json
import re
import subprocess
import sys
import time
import threading
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import xml.parsers.expat

MAX_PDF_BYTES = 15 * 1024 * 1024
MAX_TEXT_CHARS = 1_000_000
MAX_PAGES = 100
MAX_CANDIDATES = 100
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
PUBMED_BASE = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
ACCESSION_RE = re.compile(r'(?<![A-Za-z0-9_])(?:GSE[0-9]{1,9}|SRP[0-9]{1,9}|PRJ(?:NA|EB|DB)[0-9]{1,9})(?![A-Za-z0-9_])', re.I)
DOI_RE = re.compile(r'(?<![A-Za-z0-9])10\.[0-9]{4,9}/[^\s<>"\x00-\x1f]{1,200}', re.I)
_rate_lock = threading.Lock()
_last_request = 0.0


class PaperSourceError(ValueError):
    """Safe, user-displayable validation or discovery error."""


def _candidate(accession):
    if accession.startswith('GSE'):
        kind, url = 'GEO', 'https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=' + accession
    elif accession.startswith('SRP'):
        kind, url = 'SRA', 'https://www.ncbi.nlm.nih.gov/sra/?term=' + accession
    else:
        kind, url = 'BioProject', 'https://www.ncbi.nlm.nih.gov/bioproject/?term=' + accession
    return dict(accession=accession, kind=kind, url=url, pages=[], verified=False)


def _extract_pages(pages, source, warnings=None):
    accessions, dois = {}, {}
    warnings = list(warnings or [])
    remaining = MAX_TEXT_CHARS
    truncated = False
    for page_number, raw in enumerate(pages, 1):
        if page_number > MAX_PAGES or remaining <= 0:
            truncated = True
            break
        text = str(raw or '')[:remaining]
        if len(str(raw or '')) > remaining:
            truncated = True
        remaining -= len(text)
        for match in ACCESSION_RE.finditer(text):
            key = match.group().upper()
            if key not in accessions:
                if len(accessions) >= MAX_CANDIDATES:
                    truncated = True
                    continue
                accessions[key] = _candidate(key)
            if page_number not in accessions[key]['pages']:
                accessions[key]['pages'].append(page_number)
        for match in DOI_RE.finditer(text):
            key = match.group().rstrip('.,;:)]}').lower()
            if key not in dois:
                if len(dois) >= MAX_CANDIDATES:
                    truncated = True
                    continue
                dois[key] = dict(doi=key, pages=[])
            if page_number not in dois[key]['pages']:
                dois[key]['pages'].append(page_number)
    if truncated:
        warnings.append('Extraction limits reached; some pages or candidates were omitted.')
    if not accessions:
        warnings.append('No explicit dataset accession found. Scanned PDFs need OCR, which is not provided.')
    warnings.append('Candidates are literal mentions, not verified study datasets or available count matrices. Review their original context and repository metadata.')
    return dict(source=source, accessions=list(accessions.values()), dois=list(dois.values()), warnings=warnings)


def extract_text(text):
    """Extract literal identifiers locally; text is never executed or transmitted."""
    if not isinstance(text, str):
        raise PaperSourceError('Paper text must be a string.')
    return _extract_pages([text], 'text')


def _parse_pdf_local(data):
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise PaperSourceError('PDF extraction requires the optional pypdf package. Paste the data-availability text instead.') from exc
    try:
        reader = PdfReader(io.BytesIO(data), strict=True)
        if reader.is_encrypted:
            raise PaperSourceError('Encrypted PDFs are not supported. Use an unencrypted PDF or paste its data-availability text.')
        count = len(reader.pages)
        warnings = ['PDF exceeds 100 pages; only the first 100 are inspected.'] if count > MAX_PAGES else []
        pages = (reader.pages[i].extract_text() or '' for i in range(min(count, MAX_PAGES)))
        return _extract_pages(pages, 'pdf', warnings)
    except PaperSourceError:
        raise
    except Exception as exc:
        raise PaperSourceError('Could not read this PDF. It may be malformed, unsupported, or exceed parsing limits.') from exc


def extract_pdf(data, filename='paper.pdf'):
    """Parse PDF bytes in a local worker (20s timeout; Unix memory/CPU limits).

    Filename is informational only and is never used as a path or shell input.
    No paper content is sent to PubMed or any other service.
    """
    if not isinstance(data, bytes) or not data or len(data) > MAX_PDF_BYTES:
        raise PaperSourceError('Upload a nonempty PDF of at most 15 MiB.')
    if not data.startswith(b'%PDF-'):
        raise PaperSourceError('The uploaded file does not have a PDF header.')
    try:
        result = subprocess.run([sys.executable, __file__, '--pdf-worker'], input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False)
        if result.returncode != 0:
            raise PaperSourceError('PDF parsing failed or exceeded local resource limits.')
        payload = json.loads(result.stdout)
        if 'error' in payload:
            raise PaperSourceError(payload['error'])
        return payload
    except subprocess.TimeoutExpired as exc:
        raise PaperSourceError('PDF parsing exceeded the 20-second limit. Try the data-availability text instead.') from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise PaperSourceError('The local PDF parser is unavailable.') from exc


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PaperSourceError('Unexpected redirect from the public literature service.')


def _pubmed_bytes(endpoint, params, accept):
    global _last_request
    if endpoint not in ('esearch.fcgi', 'esummary.fcgi', 'efetch.fcgi'):
        raise PaperSourceError('Unsupported literature endpoint.')
    url = PUBMED_BASE + endpoint + '?' + urllib.parse.urlencode(params)
    try:
        # Keep this process below NCBI's anonymous three-requests-per-second limit.
        with _rate_lock:
            time.sleep(max(0, 0.36 - (time.monotonic() - _last_request)))
            _last_request = time.monotonic()
        req = urllib.request.Request(url, headers={'User-Agent': 'EasyMultiProfiler-PaperDiscovery/1.0', 'Accept': accept})
        with urllib.request.build_opener(_NoRedirect()).open(req, timeout=12) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
        if len(raw) > MAX_RESPONSE_BYTES:
            raise PaperSourceError('Literature metadata response exceeds the size limit.')
        return raw
    except PaperSourceError:
        raise
    except Exception as exc:
        raise PaperSourceError('Public PubMed search is unavailable. Please try again later.') from exc


def _pubmed_json(endpoint, params):
    try:
        data = json.loads(_pubmed_bytes(endpoint, params, 'application/json'))
        if not isinstance(data, dict) or data.get('error'):
            raise PaperSourceError('The literature service returned an invalid response.')
        return data
    except (ValueError, UnicodeError) as exc:
        raise PaperSourceError('The literature service returned invalid JSON metadata.') from exc


def _safe_pubmed_xml(raw):
    """Preflight bounded XML with Expat; no entity declarations or resolution.

    PubMed's ordinary external DOCTYPE is permitted but never fetched. Internal
    entity definitions and any request to resolve external entities are rejected.
    """
    if not isinstance(raw, bytes) or len(raw) > MAX_RESPONSE_BYTES:
        raise PaperSourceError('Literature XML response exceeds the size limit.')
    parser = xml.parsers.expat.ParserCreate()
    depth, nodes, chars = 0, 0, 0

    def start(name, attrs):
        nonlocal depth, nodes
        depth += 1
        nodes += 1
        if depth > 64 or nodes > 20000:
            raise PaperSourceError('Literature XML exceeds structural limits.')

    def end(name):
        nonlocal depth
        depth -= 1

    def content(text):
        nonlocal chars
        chars += len(text)
        if chars > 200000:
            raise PaperSourceError('Literature XML exceeds text limits.')

    def reject(*args):
        raise PaperSourceError('Literature XML entity declarations are not supported.')

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = content
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = reject
    parser.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    try:
        parser.Parse(raw, True)
        return ET.fromstring(raw)
    except (xml.parsers.expat.ExpatError, ET.ParseError) as exc:
        raise PaperSourceError('The literature service returned malformed XML.') from exc


def fetch_pubmed_abstract(pmid):
    """Read one selected public article's title/abstract and literal candidates.

    Sends only a validated PMID to NCBI. Does not fetch full text or follow links.
    Candidate sections are textual provenance, not PDF page numbers.
    """
    if not isinstance(pmid, str) or not re.fullmatch(r'[1-9][0-9]{0,11}', pmid):
        raise PaperSourceError('Enter a valid numeric PubMed PMID.')
    raw = _pubmed_bytes('efetch.fcgi', dict(db='pubmed', id=pmid, retmode='xml', rettype='abstract'), 'application/xml')
    root = _safe_pubmed_xml(raw)
    records = [x for x in root.findall('./PubmedArticle') if x.findtext('./MedlineCitation/PMID') == pmid]
    if len(records) != 1:
        raise PaperSourceError('The selected PubMed article was not returned by the literature service.')
    record = records[0]
    article = record.find('./MedlineCitation/Article')
    if article is None:
        raise PaperSourceError('The selected PubMed record has no article metadata.')

    def plain(element):
        return ''.join(element.itertext()).strip() if element is not None else ''

    title = plain(article.find('./ArticleTitle'))
    abstract_parts = [plain(x) for x in article.findall('./Abstract/AbstractText')]
    abstract = '\n\n'.join(x for x in abstract_parts if x)
    sections = [('title', title), ('abstract', abstract)]
    metadata_dois = [plain(x) for x in record.findall('./PubmedData/ArticleIdList/ArticleId') if x.get('IdType') == 'doi']
    sections.extend(('article_metadata', value) for value in metadata_dois)
    accessions, dois = {}, {}
    for section, text in sections:
        found = _extract_pages([text], 'pubmed_abstract')
        for key, collection in [('accessions', accessions), ('dois', dois)]:
            if section == 'article_metadata' and key == 'accessions':
                continue
            field = 'accession' if key == 'accessions' else 'doi'
            for candidate in found[key]:
                identifier = candidate[field]
                if identifier not in collection:
                    if len(collection) >= MAX_CANDIDATES:
                        continue
                    collection[identifier] = dict(candidate, pages=[], pmid=pmid, sections=[])
                if section not in collection[identifier]['sections']:
                    collection[identifier]['sections'].append(section)
    url = 'https://pubmed.ncbi.nlm.nih.gov/' + pmid + '/'
    links = [dict(kind='PubMed', url=url)]
    for item in record.findall('./PubmedData/ArticleIdList/ArticleId'):
        value = plain(item)
        if item.get('IdType') == 'pmc' and re.fullmatch(r'PMC[0-9]{1,12}', value):
            links.append(dict(kind='PMC', url='https://pmc.ncbi.nlm.nih.gov/articles/' + value + '/'))
    warnings = ['Only the selected article title, abstract, and DOI metadata were inspected. Full text and supplementary files were not fetched.',
                'Candidates are literal mentions, not verified study datasets or available count matrices. Review their original context and repository metadata.']
    if not abstract:
        warnings.append('PubMed provides no abstract for this article. Open the paper or upload its PDF to inspect data availability.')
    if not accessions:
        warnings.append('No explicit dataset accession was found in the available title/abstract. This does not mean the paper has no public data; inspect the full paper data-availability section.')
    if len(links) == 1:
        warnings.append('No PMC full-text link was reported for this record; publisher access may be required.')
    if len(accessions) == MAX_CANDIDATES or len(dois) == MAX_CANDIDATES:
        warnings.append('Candidate limit reached; additional identifiers may have been omitted.')
    return dict(source='pubmed_abstract', pmid=pmid, title=title, abstract=abstract,
                has_abstract=bool(abstract), url=url, links=links,
                accessions=list(accessions.values()), dois=list(dois.values()), warnings=warnings)


def search_pubmed(query, limit=10):
    """Send only the explicit keyword query to fixed NCBI endpoints, never PDF text.

    Returns metadata; accession matches in article titles are unverified mentions.
    Does not fetch abstracts, full text, supplements, or sequencing files.
    """
    if not isinstance(query, str) or not query.strip() or len(query) > 300 or any(ord(c) < 32 for c in query):
        raise PaperSourceError('Enter a public literature keyword query of 1–300 characters.')
    if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 20:
        raise PaperSourceError('The article limit must be an integer between 1 and 20.')
    query = query.strip()
    search = _pubmed_json('esearch.fcgi', dict(db='pubmed', term=query, retmode='json', retmax=limit, sort='relevance'))
    result = search.get('esearchresult', {})
    if not isinstance(result, dict) or not isinstance(result.get('idlist', []), list):
        raise PaperSourceError('The literature service returned invalid search metadata.')
    ids = [str(x) for x in result.get('idlist', []) if re.fullmatch(r'[0-9]{1,12}', str(x))][:limit]
    articles = []
    if ids:
        summary = _pubmed_json('esummary.fcgi', dict(db='pubmed', id=','.join(ids), retmode='json')).get('result', {})
        if not isinstance(summary, dict):
            raise PaperSourceError('The literature service returned invalid article metadata.')
        for pmid in ids:
            item = summary.get(pmid, {})
            if not isinstance(item, dict) or not item.get('title'):
                continue
            title = str(item['title'])[:2000]
            article_ids = item.get('articleids', [])
            dois = [str(x.get('value', ''))[:220] for x in article_ids if isinstance(x, dict) and x.get('idtype') == 'doi'] if isinstance(article_ids, list) else []
            articles.append(dict(pmid=pmid, title=title, journal=str(item.get('fulljournalname', ''))[:500],
                                 date=str(item.get('pubdate', ''))[:100], dois=dois[:10],
                                 url='https://pubmed.ncbi.nlm.nih.gov/' + pmid + '/',
                                 accessions=_extract_pages([title], 'pubmed_title')['accessions']))
    return dict(source='pubmed', query=query, articles=articles,
                warnings=['Only public article metadata is searched. A matching article does not verify dataset relevance or count-matrix availability. Open the paper or upload a PDF to find data-availability accessions.'])


if __name__ == '__main__' and sys.argv[1:] == ['--pdf-worker']:
    try:
        try:
            import resource
            resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024, 512 * 1024 * 1024))
            resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
        except ImportError:
            pass  # Windows still enforces parent wall-clock and input limits.
        body = sys.stdin.buffer.read(MAX_PDF_BYTES + 1)
        if len(body) > MAX_PDF_BYTES:
            raise PaperSourceError('PDF exceeds the size limit.')
        print(json.dumps(_parse_pdf_local(body)))
    except Exception as exc:
        print(json.dumps({'error': str(exc) if isinstance(exc, PaperSourceError) else 'PDF parsing failed.'}))
