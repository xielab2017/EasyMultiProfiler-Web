"""Offline sample-metadata tests. No raw reads, analysis or network requests."""
import csv
import gzip
import hashlib
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import processed_data as p

class LibraryNameTests(unittest.TestCase):
    def test_named_library_field_is_exact_and_ambiguities_remain_unmatched(self):
        records=[{'accession':'GSM1','descriptions':['Library name: A1']},{'accession':'GSM2','descriptions':['Library name: A2']}]
        matched=p.match_samples(['A1','A2','A','a1'],records)
        self.assertEqual([x['sample']['accession'] for x in matched[:2]],['GSM1','GSM2'])
        self.assertEqual(matched[0]['matched_fields'],['Sample_description.Library_name'])
        self.assertIsNone(matched[2]['sample']);self.assertIsNone(matched[3]['sample'])
        self.assertIsNone(p.match_samples(['A1'],records+[{'accession':'GSM3','descriptions':['Library name: A1']}])[0]['sample'])

ACCESSION = 'GSE60450'
BASE = 'https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450'
MATRIX_URL = BASE + '/matrix/GSE60450_series_matrix.txt.gz'
SOFT_URL = BASE + '/soft/GSE60450_family.soft.gz'
MATRIX = '''!Series_geo_accession\t"GSE60450"
!Series_platform_id\t"GPL1"
!Sample_geo_accession\t"GSM2"\t"GSM1"
!Sample_title\t"second sample"\t"first sample"
!Sample_description\t"column_B"\t"column_A"
!Sample_description\t"shared description"\t"shared description"
!Sample_characteristics_ch1\t"reported stage: B"\t"reported stage: A"
!Sample_source_name_ch1\t"reported source B"\t"reported source A"
!Sample_platform_id\t"GPL1"\t"GPL1"
!series_matrix_table_begin
"ID_REF"\t"GSM2"\t"GSM1"
"probe1"\t5\t9
!series_matrix_table_end
'''
SOFT = '''^DATABASE = GeoMiame
^SERIES = GSE60450
!Series_geo_accession = GSE60450
!Series_sample_id = GSM1
!Series_sample_id = GSM2
^PLATFORM = GPL1
!Platform_geo_accession = GPL1
^SAMPLE = GSM1
!Sample_geo_accession = GSM1
!Sample_title = first sample
!Sample_description = column_A
!Sample_description = shared description
!Sample_characteristics_ch1 = reported stage: A
!Sample_source_name_ch1 = reported source A
!Sample_platform_id = GPL1
!Sample_series_id = GSE60450
!Sample_data_row_count = 0
^SAMPLE = GSM2
!Sample_geo_accession = GSM2
!Sample_title = second sample
!Sample_description = column_B
!Sample_description = shared description
!Sample_characteristics_ch1 = reported stage: B
!Sample_source_name_ch1 = reported source B
!Sample_platform_id = GPL2
!Sample_series_id = GSE60450
!Sample_data_row_count = 0
'''


class FakeOpener:
    def __init__(self, responses):
        self.responses = responses
        self.urls = []

    def open(self, request, timeout):
        url = request.full_url
        self.urls.append(url)
        value = self.responses[url]
        if isinstance(value, Exception):
            raise value
        return io.BytesIO(value)


def compressed(text):
    return gzip.compress(text.encode(), mtime=0)


def missing(url=MATRIX_URL):
    return HTTPError(url, 404, 'Not Found', {}, None)


class MatrixAnnotationTests(unittest.TestCase):
    def fetch(self, responses, labels=None):
        opener = FakeOpener(responses)
        with patch.object(p, 'build_opener', return_value=opener):
            result = p.fetch_annotations(ACCESSION, labels)
        return result, opener.urls

    def test_primary_matrix_only_and_source_hash(self):
        payload = compressed(MATRIX)
        result, urls = self.fetch({MATRIX_URL: payload}, ['column_A', 'column_B'])
        self.assertEqual(urls, [MATRIX_URL])
        self.assertEqual(result['source_format'], 'series_matrix')
        self.assertEqual(result['sha256'], hashlib.sha256(payload).hexdigest())
        self.assertEqual(result['bytes'], len(payload))
        self.assertFalse(result['publisher_checksum_verified'])
        self.assertEqual(result['warnings'], [])
        self.assertEqual(result['sources'][0]['source_url'], MATRIX_URL)
        self.assertEqual([x['sample']['accession'] for x in p.match_samples(['column_A', 'column_B'], result['records'])], ['GSM1', 'GSM2'])

    def test_missing_matrix_uses_one_official_soft(self):
        payload = compressed(SOFT)
        result, urls = self.fetch({MATRIX_URL: missing(), SOFT_URL: payload}, ['column_B', 'column_A'])
        self.assertEqual(urls, [MATRIX_URL, SOFT_URL])
        self.assertEqual(result['source_format'], 'family_soft')
        self.assertEqual(result['sha256'], hashlib.sha256(payload).hexdigest())
        self.assertIn('series_matrix_unavailable', result['warnings'])
        self.assertEqual([x['sample']['accession'] for x in p.match_samples(['column_B', 'column_A'], result['records'])], ['GSM2', 'GSM1'])

    def test_wrong_series_falls_back_without_accepting_wrong_records(self):
        wrong = MATRIX.replace('"GSE60450"', '"GSE60451"')
        result, urls = self.fetch({MATRIX_URL: compressed(wrong), SOFT_URL: compressed(SOFT)})
        self.assertEqual(len(urls), 2)
        self.assertEqual(result['source_format'], 'family_soft')
        self.assertIn('series_matrix_metadata_mismatch_or_invalid', result['warnings'])
        self.assertEqual(len(result['sources']), 2)

    def test_mismatched_columns_fall_back_to_complete_descriptions(self):
        partial = MATRIX.replace('"column_B"', '"old_column_B"')
        result, _ = self.fetch({MATRIX_URL: compressed(partial), SOFT_URL: compressed(SOFT)}, ['column_A', 'column_B'])
        self.assertEqual(result['source_format'], 'family_soft')
        self.assertIn('series_matrix_columns_not_uniquely_matched', result['warnings'])
        self.assertTrue(all(x['status'] == 'exact' for x in p.match_samples(['column_A', 'column_B'], result['records'])))

    def test_multiple_platform_matrix_falls_back_without_listing_or_platform_fetches(self):
        multi = MATRIX.replace('!Series_platform_id\t"GPL1"', '!Series_platform_id\t"GPL1"\n!Series_platform_id\t"GPL2"')
        result, urls = self.fetch({MATRIX_URL: compressed(multi), SOFT_URL: compressed(SOFT)})
        self.assertEqual(urls, [MATRIX_URL, SOFT_URL])
        self.assertIn('series_matrix_multiple_platforms', result['warnings'])
        self.assertEqual(result['records'][1]['platform_ids'], ['GPL2'])

    def test_per_sample_multiple_platforms_also_trigger_fallback(self):
        multi = MATRIX.replace('!Sample_platform_id\t"GPL1"\t"GPL1"', '!Sample_platform_id\t"GPL1"\t"GPL2"')
        result, _ = self.fetch({MATRIX_URL: compressed(multi), SOFT_URL: compressed(SOFT)})
        self.assertEqual(result['source_format'], 'family_soft')

    def test_metadata_fields_are_retained_without_inferred_groups(self):
        records = p.parse_family_sample_annotations(SOFT, ACCESSION)
        self.assertEqual(records[0]['characteristics'], ['reported stage: A'])
        self.assertEqual(records[0]['source_names'], ['reported source A'])
        for record in records:
            self.assertNotIn('group', record)
            self.assertNotIn('condition', record)
            self.assertNotIn('contrast', record)

    def test_matching_is_exact_case_sensitive_not_title_substring_or_order(self):
        records = p.parse_sample_annotations(MATRIX)
        result = p.match_samples(['column_A', 'column_B', 'first sample', 'column', 'COLUMN_A', ' column_A', ''], records)
        self.assertEqual([x['sample']['accession'] for x in result[:2]], ['GSM1', 'GSM2'])
        self.assertEqual(result[0]['matched_fields'], ['Sample_description'])
        self.assertTrue(all(x['status'] == 'unmatched_or_ambiguous' for x in result[2:]))
        self.assertEqual(p.match_samples(['GSM1'], records)[0]['matched_fields'], ['Sample_geo_accession'])

    def test_shared_descriptions_duplicate_labels_and_alias_collisions_are_ambiguous(self):
        records = p.parse_sample_annotations(MATRIX)
        for labels in [['shared description'], ['column_A', 'column_A'], ['GSM1', 'column_A']]:
            with self.subTest(labels=labels):
                self.assertTrue(all(x['sample'] is None for x in p.match_samples(labels, records)))

    def test_matrix_invalid_accessions_and_ragged_rows_are_rejected(self):
        for text in [MATRIX.replace('"GSM2"', '"GSM1"'), MATRIX.replace('"GSM2"', '"not-a-GSM"'), MATRIX.replace('"column_B"\t"column_A"', '"column_B"')]:
            with self.subTest(text=text[:100]), self.assertRaises(p.m.MetadataError):
                p.parse_sample_annotations(text, ACCESSION)

    def test_soft_requires_correct_series_and_complete_unique_membership(self):
        cases = [SOFT.replace('GSE60450', 'GSE60451'), SOFT.replace('!Series_sample_id = GSM2\n', ''),
                 SOFT.replace('!Sample_geo_accession = GSM1', '!Sample_geo_accession = GSM9'),
                 SOFT + '^SAMPLE = GSM1\n!Sample_geo_accession = GSM1\n',
                 SOFT.replace('!Series_geo_accession = GSE60450\n', '')]
        for text in cases:
            with self.subTest(text=text[:100]), self.assertRaises(p.m.MetadataError):
                p.parse_family_sample_annotations(text, ACCESSION)

    def test_html_or_invalid_gzip_falls_back(self):
        for payload in [b'<html>Not a matrix</html>', compressed('<html>Not metadata</html>')]:
            with self.subTest(payload=payload):
                result, urls = self.fetch({MATRIX_URL: payload, SOFT_URL: compressed(SOFT)})
                self.assertEqual(result['source_format'], 'family_soft')
                self.assertEqual(len(urls), 2)

    def test_unknown_columns_remain_unmatched_after_fallback(self):
        result, _ = self.fetch({MATRIX_URL: missing(), SOFT_URL: compressed(SOFT)}, ['unknown'])
        self.assertIn('family_soft_columns_not_uniquely_matched', result['warnings'])
        self.assertIsNone(p.match_samples(['unknown'], result['records'])[0]['sample'])

    def test_unavailable_fallback_keeps_partial_same_series_metadata_explicit(self):
        result, urls = self.fetch({MATRIX_URL: compressed(MATRIX), SOFT_URL: missing(SOFT_URL)}, ['unknown'])
        self.assertEqual(len(urls), 2)
        self.assertEqual(result['source_format'], 'series_matrix')
        self.assertIn('family_soft_unavailable_or_invalid', result['warnings'])
        self.assertIsNone(p.match_samples(['unknown'], result['records'])[0]['sample'])

    def test_both_sources_absent_raise_without_extra_fetches(self):
        opener = FakeOpener({MATRIX_URL: missing(), SOFT_URL: missing(SOFT_URL)})
        with patch.object(p, 'build_opener', return_value=opener), self.assertRaisesRegex(p.m.MetadataError, 'unavailable'):
            p.fetch_annotations(ACCESSION)
        self.assertEqual(opener.urls, [MATRIX_URL, SOFT_URL])

    def test_compressed_and_expanded_bounds_stop_without_bypass(self):
        for setting, limit, payload in [('MAX_ANNOTATION_DOWNLOAD', 8, b'x' * 9), ('MAX_UNCOMPRESSED', 8, compressed(MATRIX))]:
            opener = FakeOpener({MATRIX_URL: payload})
            with self.subTest(setting=setting), patch.object(p, setting, limit), patch.object(p, 'build_opener', return_value=opener), self.assertRaises(p.m.MetadataError):
                p.fetch_annotations(ACCESSION)
            self.assertEqual(opener.urls, [MATRIX_URL])

    def test_soft_compressed_bound_is_identical(self):
        opener = FakeOpener({MATRIX_URL: missing(), SOFT_URL: b'x' * 9})
        with patch.object(p, 'MAX_ANNOTATION_DOWNLOAD', 8), patch.object(p, 'build_opener', return_value=opener), self.assertRaises(p.m.MetadataError):
            p.fetch_annotations(ACCESSION)
        self.assertEqual(opener.urls, [MATRIX_URL, SOFT_URL])

    def test_access_denial_rate_limit_or_redirect_does_not_retry_another_endpoint(self):
        errors = [HTTPError(MATRIX_URL, code, 'blocked', {}, None) for code in [401, 403, 429, 500]]
        errors.append(p.m.MetadataError('Metadata redirect refused; inspect the official endpoint.'))
        for error in errors:
            opener = FakeOpener({MATRIX_URL: error})
            with self.subTest(error=error), patch.object(p, 'build_opener', return_value=opener), self.assertRaises(p.m.MetadataError):
                p.fetch_annotations(ACCESSION)
            self.assertEqual(opener.urls, [MATRIX_URL])

    def test_invalid_inputs_make_no_request(self):
        with patch.object(p, 'build_opener') as opener:
            for value in [None, 'GSE1/../../other', 'GSM1', 'https://evil.test']:
                with self.subTest(value=value), self.assertRaises(p.m.MetadataError):
                    p.fetch_annotations(value)
            with self.assertRaises(p.m.MetadataError):
                p.fetch_annotations(ACCESSION, [None])
            opener.assert_not_called()

    def test_available_official_public_fixture_maps_all_twelve_columns(self):
        fixture_dir = Path(__file__).parents[3] / 'public_validation_inputs'
        soft_path = fixture_dir / 'GSE60450_family.soft.gz'
        counts_path = fixture_dir / 'GSE60450_Lactation-GenewiseCounts.txt.gz'
        if not soft_path.exists() or not counts_path.exists():
            self.skipTest('Optional official public fixture not present; synthetic coverage is self-contained')
        data = soft_path.read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), '4ed19bb55731ec6a8c534de63505896ad5b1731b891960a813ff3e95a703338b')
        records = p.parse_family_sample_annotations(gzip.decompress(data).decode(), ACCESSION)
        with gzip.open(counts_path, 'rt') as handle:
            header = next(csv.reader(handle, delimiter='\t'))
        self.assertEqual(header[:2], ['EntrezGeneID', 'Length'])
        matches = p.match_samples(header[2:], records)
        self.assertEqual(len(matches), 12)
        self.assertTrue(all(x['status'] == 'exact' for x in matches))
        self.assertTrue(all(x['matched_fields'] == ['Sample_description'] for x in matches))
        self.assertEqual([x['sample']['accession'] for x in matches],
                         ['GSM1480297', 'GSM1480298', 'GSM1480299', 'GSM1480300', 'GSM1480301', 'GSM1480302',
                          'GSM1480291', 'GSM1480292', 'GSM1480293', 'GSM1480294', 'GSM1480295', 'GSM1480296'])


if __name__ == '__main__':
    unittest.main()
