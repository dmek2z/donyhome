#!/usr/bin/env python3
"""Package a DEBUG native fixture after swift build; never ship this bundle."""
from pathlib import Path
import shutil, plistlib, subprocess, uuid
root=Path(__file__).resolve().parents[1]
app=root/'build/DonyActionFixture.app'
if app.exists(): shutil.rmtree(app)
shutil.copytree(root/'build/DonyHome.app',app)
shutil.copy2(root/'.build/out/Products/Debug/DonyHome',app/'Contents/MacOS/DonyHome')
p=app/'Contents/Info.plist';info=plistlib.loads(p.read_bytes())
info['CFBundleIdentifier']='local.dony.ActionUIFixture'
info['CFBundleName']='DonyActionFixture'
info['CFBundleDisplayName']='도니홈 버튼 검증'
info['DonyActionFixture']=True
info['DonyFixtureDirectory']=str(root/('build/action-ui-fixture-data-' + uuid.uuid4().hex))
p.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
print(app)
