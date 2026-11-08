"""The repository DESCRIPTION is the single source of the web release version."""
import re
from pathlib import Path
DESCRIPTION=Path(__file__).resolve().parents[2]/'DESCRIPTION'
def app_version(path=DESCRIPTION):
 match=re.search(r'^Version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)\s*$',Path(path).read_text(),re.M)
 if not match:raise ValueError('DESCRIPTION contains no valid Version')
 return match.group(1)
