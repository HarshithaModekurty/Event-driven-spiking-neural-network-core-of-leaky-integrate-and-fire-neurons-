"""Install portable formal tools under ignored build/, without system changes.

Windows: python -m tools.setup_formal_tools
NuSMV is fetched from its official distribution with its published SHA256.
Yosys uses the upstream YoWASP package in a private CPython 3.11 target dir.
"""
from pathlib import Path
import hashlib
import importlib.metadata
import json
import re
import subprocess
import sys
import sysconfig
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT/'build/formal_tools'
BASE = 'https://nusmv.fbk.eu/distrib/2.7.1/'
ARCHIVE = 'NuSMV-2.7.1-win64.zip'


def fetch(url):
    # Windows curl uses the system certificate chain builder (Schannel).
    # Keep certificate verification enabled, including for the checksum URL.
    result = subprocess.run(['curl.exe', '--fail', '--location', '--silent',
                             '--show-error', '--connect-timeout', '20',
                             '--max-time', '180', url], capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def main():
    if sysconfig.get_platform().startswith('mingw'):
        # Native CPython uses Windows' trusted certificate store and wheels.
        subprocess.run(['py', '-3.11', '-m', 'tools.setup_formal_tools'], check=True)
        return
    DEST.mkdir(parents=True, exist_ok=True)
    archive = DEST/ARCHIVE
    checksum_text = fetch(BASE+ARCHIVE+'.sha256sum').decode('ascii')
    match = re.search(r'\b[0-9a-fA-F]{64}\b', checksum_text)
    if not match:
        raise RuntimeError('Official archive checksum is missing')
    expected = match.group().lower()
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        archive.write_bytes(fetch(BASE+ARCHIVE))
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise RuntimeError('NuSMV archive does not match official checksum')
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            target = (DEST/member.filename).resolve()
            if not target.is_relative_to(DEST.resolve()):
                raise RuntimeError('Archive member is outside the tool directory')
        package.extractall(DEST)
    # CPython's supported Windows wheel platform, independent of MSYS Python.
    subprocess.run([sys.executable, '-m', 'pip', 'install', '--target',
                    str(DEST/'python'), '-r', str(ROOT/'requirements-formal.txt')], check=True, timeout=300)
    nusmv = next(DEST.rglob('NuSMV.exe'))
    record = {'nusmv_version': '2.7.1', 'nusmv_url': BASE+ARCHIVE,
              'nusmv_archive_sha256': expected, 'nusmv_executable': str(nusmv.relative_to(ROOT)),
              'yosys_python_target': str((DEST/'python').relative_to(ROOT)),
              'nusmv_executable_sha256': hashlib.sha256(nusmv.read_bytes()).hexdigest(),
              'python_packages': {dist.metadata['Name']: dist.version for dist in
                                  importlib.metadata.distributions(path=[str(DEST/'python')])}}
    (DEST/'tool_versions.json').write_text(json.dumps(record, indent=2)+'\n')
    print('Portable formal tools installed in', DEST)


if __name__ == '__main__':
    main()
