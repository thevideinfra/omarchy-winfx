#!/usr/bin/env python3
"""Render the actual panel with theme/shell interface stubs (not a live shell test).
Optional dependency: PySide6-Essentials. Output: /tmp/omarchy-effects-panel.png.
"""
import os, sys
os.environ['QT_QPA_PLATFORM']='offscreen'
os.environ['QT_QUICK_BACKEND']='software'
from pathlib import Path
from PySide6.QtCore import QUrl, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtQml import QQmlComponent
base=Path('/tmp/omafx-qml-stubs')
modules={
'qs/Commons':{
'Style':'pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family:"DejaVu Sans Mono",body:13,caption:11,title:15}); function space(v) { return v } }',
'Color':'pragma Singleton\nimport QtQuick\nQtObject { property color accent:"#9ece6a"; property color foreground:"#c0caf5"; property var popups: ({text:foreground}) }',
'Util':'pragma Singleton\nimport QtQuick\nQtObject { function alpha(c,a) { return Qt.rgba(c.r,c.g,c.b,a) } }'},
'qs/Ui':{
'Panel':'import QtQuick\nItem { property var bar:null; property string moduleName; property string ipcTarget; property bool opened:false; property color barForeground:"#c0caf5"; function toggle(){opened=!opened} function close(){opened=false} function switchPanel(d){} }',
'BarIconButton':'import QtQuick\nItem { property var bar; property Component iconComponent; property string tooltipText; signal pressed(int b); implicitWidth:24; implicitHeight:24 }',
'KeyboardPanel':'''import QtQuick
Item {
property var anchorItem; property var owner; property var bar; property bool open
property var focusTarget; property real padding:12; property real contentWidth; property real contentHeight
function fittedContentWidth(v){return v} function fittedContentHeight(v){return v}
width:contentWidth+2*padding; height:contentHeight+2*padding
Rectangle { anchors.fill:parent; color:"#16161e"; border.color:"#565f89"; border.width:2; radius:8 }
default property alias contentData:container.data
Item { id:container; anchors.fill:parent; anchors.margins:parent.padding }
}''',
'PanelKeyCatcher':'import QtQuick\nItem { signal closeRequested(); signal activateRequested(); signal moveRequested(int dx,int dy); signal tabRequested(int direction) }'},
'Quickshell':{},
'Quickshell/Io':{
'Process':'import QtQuick\nItem { property var command; property bool running:false; property var stdout; property var stderr; signal exited(int code); onRunningChanged: if(running) Qt.callLater(function(){running=false}) }',
'StdioCollector':'import QtQuick\nQtObject { property bool waitForEnd; property string text:""; signal streamFinished() }'}
}
for module,items in modules.items():
 d=base/module; d.mkdir(parents=True,exist_ok=True)
 q='module '+module.replace('/','.')+'\n'
 for name,source in items.items():
  (d/(name+'.qml')).write_text(source)
  q+=('singleton ' if source.startswith('pragma Singleton') else '')+name+' 1.0 '+name+'.qml\n'
 (d/'qmldir').write_text(q)
app=QGuiApplication([]); view=QQuickView(); view.engine().addImportPath(str(base))
comp=QQmlComponent(view.engine(),QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1] / 'Panel.qml')))
if comp.isError():
 print('\n'.join(e.toString() for e in comp.errors())); sys.exit(1)
obj=comp.create()
if obj is None:
 print('\n'.join(e.toString() for e in comp.errors())); sys.exit(1)
obj.setParentItem(view.contentItem()); obj.setX(20); obj.setY(20)
obj.setProperty('loaded',True); obj.setProperty('ready',True); obj.setProperty('pEnabled',True)
obj.setProperty('backendText','HyprWindowShade · ready')
view.resize(388,650); view.setColor('#0f111a'); view.show()
def done():
 img=view.grabWindow(); img.save('/tmp/omarchy-effects-panel.png'); print('QML instantiated with interface stubs; screenshot saved'); app.quit()
QTimer.singleShot(500,done)
app.exec()
