// omacut — a dead-simple video editor: cut, split and join clips from your videos. Qt Quick UI, ffmpeg cuts.

#include <QGuiApplication>
#include <QFileInfo>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "theme.h"
#include "thumbprovider.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    // Qt's ffmpeg backend falls through to Vulkan video when VA-API is missing,
    // and on GPUs without Vulkan decode queues it then picks ffmpeg's hwaccel-only
    // av1 decoder and never falls back to dav1d, leaving the preview black. Stick
    // to the backends Qt checks codec support for, so software decode kicks in.
    // On NVIDIA, VA-API means nvidia-vaapi-driver, whose vaSyncSurface never
    // returns when the render thread maps a frame, freezing the whole window.
    if (!qEnvironmentVariableIsSet("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES",
                QFileInfo::exists("/sys/module/nvidia") ? "cuda" : "vaapi,cuda");

    // Exports run through the ffmpeg CLI, so Qt never encodes. Without this, Qt
    // probes every hardware encoder backend when it loads, which takes about two
    // seconds before the window appears on some GPUs (Vulkan alone takes ~0.9s).
    if (!qEnvironmentVariableIsSet("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES", "none");

    QGuiApplication app(argc, argv);
    app.setApplicationName("omacut");

    // Associates the window with omacut.desktop so the compositor (Wayland app_id
    // = this name) and taskbars pick up our installed icon.
    app.setDesktopFileName("omacut");
    app.setWindowIcon(QIcon::fromTheme("omacut"));

    // Modern, themeable controls (the same family Quickshell builds on).
    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    auto *provider = new ThumbProvider();
    Backend backend(provider, &app);

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);

    // The engine takes ownership of the image provider.
    engine.addImageProvider("thumbs", provider);

    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);

    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;

    // `omacut [--view] [file]`: --view starts as a plain player (the
    // default video player's desktop entry uses it), and a file opens.
    QString file;
    bool view = false;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i) == QLatin1String("--view"))
            view = true;
        else if (file.isEmpty())
            file = args.at(i);
    }
    if (view)
        engine.rootObjects().first()->setProperty("viewMode", true);
    if (!file.isEmpty())
        backend.load(file.contains(QLatin1String("://")) ? QUrl(file)
                                                         : QUrl::fromLocalFile(QFileInfo(file).absoluteFilePath()));

    return app.exec();
}
