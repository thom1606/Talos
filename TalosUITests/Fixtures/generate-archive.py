"""Real ZIP input for Finder -> Convert -> ZIP/TAR/GZIP, including an empty directory."""
import pathlib
import sys
import zipfile

path = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(path.parent / 'sample.png', 'picture.png')
    archive.writestr('nested/notes.txt', b'A file inside the archive')
    archive.writestr('empty/', b'')
