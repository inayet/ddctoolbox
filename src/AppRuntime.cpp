#include "AppRuntime.h"

#include "utils/VdcProjectManager.h"
#include "widget/ProxyStyle.h"

#include <QDebug>
#include <QFileOpenEvent>
#include <QStyleFactory>
#include <QtGlobal>

#include <model/CurveFittingOptions.h>

#define _STR(x) #x
#define STRINGIFY(x) _STR(x)

AppRuntime::AppRuntime(int &argc, char **argv) : QApplication(argc, argv) {
  qRegisterMetaType<CurveFittingOptions::AlgorithmType>();

  AppRuntime::setApplicationVersion(STRINGIFY(CURRENT_APP_VERSION));
  AppRuntime::setApplicationName("DDCToolbox");
  AppRuntime::setOrganizationName("Tim Schneeberger");

  AppRuntime::setStyle(new ProxyStyle("Fusion"));
  AppRuntime::setPalette(AppRuntime::style()->standardPalette());
  /* Context-help button attribute is intentionally omitted for Qt6 builds.
     The Qt5-only attribute has been removed to keep the code clean and
     Qt6-compatible. */

#ifdef __APPLE__
  this->setStyleSheet("* {font-size: 13px;}");
#endif

  _window = new VdcEditorWindow();

  if (argc > 1) {
    VdcProjectManager::instance().loadProject(QString::fromLocal8Bit(argv[1]));
  }

  _window->show();
}

AppRuntime::~AppRuntime() { _window->deleteLater(); }

bool AppRuntime::event(QEvent *event) {
  switch (event->type()) {
  case QEvent::FileOpen: {
    QFileOpenEvent *fileOpenEvent = static_cast<QFileOpenEvent *>(event);
    if (fileOpenEvent) {
      auto path = fileOpenEvent->file();
      qDebug() << "File open event received:" << path;
      if (!path.isEmpty() && _window) {
        VdcProjectManager::instance().loadProject(path);
        return true;
      }
    }
  } break;
  }
  return QApplication::event(event);
}
