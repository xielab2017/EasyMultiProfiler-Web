"""Shared upload/worker limits for the frontend proxy and PDF service."""
import os

MAX_PDF_MIB = int(os.environ.get('EMP_PDF_MAX_MIB', '100'))
if not 1 <= MAX_PDF_MIB <= 512:
    raise ValueError('EMP_PDF_MAX_MIB must be an integer from 1 to 512')
MAX_PDF_BYTES = MAX_PDF_MIB * 1024 * 1024
PDF_TIMEOUT_SECONDS = 60
PDF_CPU_SECONDS = 45


def capabilities():
    return {'max_bytes': MAX_PDF_BYTES, 'max_mib': MAX_PDF_MIB,
            'max_pages': 100, 'max_text_characters': 1_000_000,
            'timeout_seconds': PDF_TIMEOUT_SECONDS, 'ocr': False}
