#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import pathlib,json
root=pathlib.Path('build/AnymeXDependencies.yml')
dependencies=json.loads(root.read_text())['targets']['AnimeCompanion']['dependencies']
project={
 'name':'ExtensionStartup',
 'options':{'deploymentTarget':{'iOS':'17.0'}},
 'settings':{'base':{'SWIFT_VERSION':'5.0','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1,2'}},
 'targets':{
  'ExtensionStartupHost':{
   'type':'application','platform':'iOS',
   'sources':[{'path':'Tests/ExtensionStartupHost.swift'}, {'path':'build/AnymeXFrameworks/Runtime','type':'folder','buildPhase':'resources'}],
   'dependencies':dependencies,
   'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'com.animecompanion.extension-startup','GENERATE_INFOPLIST_FILE':'YES','OTHER_LDFLAGS':'$(inherited) -ObjC'}}},
  'ExtensionStartupTests':{
   'type':'bundle.unit-test','platform':'iOS','sources':[{'path':'Tests/ExtensionStartupTests'}],
   'dependencies':[{'target':'ExtensionStartupHost'}]+[{**d,'embed':False} for d in dependencies],
   'settings':{'base':{'GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/ExtensionStartupHost.app/ExtensionStartupHost','BUNDLE_LOADER':'$(TEST_HOST)'}}}},
 'schemes':{'ExtensionStartup':{'build':{'targets':{'ExtensionStartupHost':'all'}},'test':{'targets':['ExtensionStartupTests']}}}}
# Write at the repository root so all source/framework paths remain relative.
pathlib.Path('ExtensionStartup.yml').write_text(json.dumps(project,indent=2))
PY
xcodegen generate --spec ExtensionStartup.yml
python3 - <<'PY'
import json,subprocess,pathlib
values=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
choices=[(runtime,device) for runtime,items in values.items() if 'iOS-18' in runtime or 'iOS-26' in runtime for device in items if device.get('isAvailable') and device['name'].startswith('iPhone')]
choices.sort(key=lambda item: (0 if 'iOS-18' in item[0] else 1,item[0],item[1]['name']))
if not choices: raise SystemExit('No iPhone simulator available')
identifier=choices[0][1]['udid']
subprocess.run(['xcrun','simctl','boot',identifier],timeout=90,check=False)
subprocess.run(['xcrun','simctl','bootstatus',identifier,'-b'],timeout=240,check=True)
pathlib.Path('build/extension-startup-device.txt').write_text(identifier)
# iOS 18's hosted runtime may omit the WebKit Swift overlay from its default
# search path. Use the selected simulator's own copy, as in check-simulator.sh.
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtime=next(r for r in runtimes if r['identifier']==choices[0][0])
root=pathlib.Path(runtime['bundlePath'])/'Contents/Resources/RuntimeRoot'
for relative in ['System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.dylib','usr/lib/swift/libswiftWebKit.dylib']:
 library=root/relative
 if library.is_file():
  output=pathlib.Path('build/ExtensionStartup/Build/Products/Debug-iphonesimulator')
  output.mkdir(parents=True,exist_ok=True)
  link=output/library.name
  if not link.exists():link.symlink_to(library)
  break
PY
simulator_id="$(cat build/extension-startup-device.txt)"
xcodebuild -project ExtensionStartup.xcodeproj -scheme ExtensionStartup \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/ExtensionStartup -resultBundlePath build/ExtensionStartup.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
python3 scripts/check-anymex-bundle.py build/ExtensionStartup/Build/Products/Debug-iphonesimulator/ExtensionStartupHost.app --simulator
