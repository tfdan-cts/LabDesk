import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/labdesk/screens/install_screen.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

const _agreementUrl = 'https://rustdesk.com/privacy.html';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    // The console theme is imposed on this window rather than inherited: the
    // installer is the first thing anyone sees of LabDesk, and it should not
    // change identity with whatever theme mode the machine happens to carry.
    return Theme(
      data: C.theme(),
      child: DragToResizeArea(
        resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
        enableResizeEdges: windowManagerEnableResizeEdges,
        child: Container(
          child: Scaffold(
              backgroundColor: C.bg,
              body: DesktopTab(controller: tabController)),
        ),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  final RxString path = ''.obs;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;

  _InstallPageBodyState() {
    path.value = bind.installInstallPath();
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => InstallView(
          appName: appName,
          t: translate,
          installPath: path.value,
          onChangePath: selectInstallPath,
          startMenu: startmenu.value,
          onStartMenu: (v) => startmenu.value = v,
          desktopIcon: desktopicon.value,
          onDesktopIcon: (v) => desktopicon.value = v,
          printer: printer.value,
          onPrinter: (v) => printer.value = v,
          enabled: btnEnabled.value,
          busy: showProgress.value,
          // The FFI reads "show", but upstream uses it as the Offstage flag,
          // so a true value hides the button. Kept as it behaves.
          hideRunWithoutInstall: bind.installShowRunWithoutInstall(),
          onInstall: install,
          onCancel: () => windowManager.close(),
          onRunWithoutInstall: () => bind.installRunWithoutInstall(),
          agreementUrl: _agreementUrl,
          onOpenAgreement: () => launchUrlString(_agreementUrl),
        ));
  }

  void install() {
    do_install() {
      btnEnabled.value = false;
      showProgress.value = true;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: path.value);
    }

    do_install();
  }

  void selectInstallPath() async {
    String? install_path =
        await FilePicker.platform.getDirectoryPath(initialDirectory: path.value);
    if (install_path != null) {
      path.value = join(install_path, await bind.mainGetAppName());
    }
  }
}
