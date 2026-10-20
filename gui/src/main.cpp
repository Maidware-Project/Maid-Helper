#include "mainwindow.h"

#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDialog>
#include <QIcon>
#include <QInputDialog>
#include <QLineEdit>
#include <QStyle>
#include <QTextStream>
#include <QTimer>

#include <cstring>

namespace {
int runAskpass(int argc, char **argv, int optionIndex)
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("maid-helper-askpass"));

    QInputDialog dialog;
    dialog.setWindowTitle(QStringLiteral("Maid Helper - administrator password"));
    dialog.setInputMode(QInputDialog::TextInput);
    dialog.setTextEchoMode(QLineEdit::Password);
    dialog.setLabelText(optionIndex + 1 < argc
                            ? QString::fromLocal8Bit(argv[optionIndex + 1])
                            : QStringLiteral("Password:"));
    dialog.setWindowFlag(Qt::WindowStaysOnTopHint);
    dialog.show();
    dialog.raise();
    dialog.activateWindow();

    if (dialog.exec() != QDialog::Accepted)
        return 1;

    QTextStream out(stdout);
    out << dialog.textValue() << Qt::endl;
    return 0;
}

QIcon appIcon()
{
    QIcon icon = QIcon::fromTheme(QStringLiteral("maid-helper"));
    if (icon.isNull())
        icon = QIcon::fromTheme(QStringLiteral("system-help"));
    if (icon.isNull())
        icon = QIcon::fromTheme(QStringLiteral("dialog-information"));
    if (icon.isNull())
        icon = QApplication::style()->standardIcon(QStyle::SP_MessageBoxInformation);
    return icon;
}
}

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--askpass") == 0)
            return runAskpass(argc, argv, i);
    }

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("maid-helper"));
    QApplication::setApplicationDisplayName(QStringLiteral("Maid Helper"));
    QApplication::setOrganizationName(QStringLiteral("Maidware"));
    QApplication::setApplicationVersion(QStringLiteral(MAID_HELPER_VERSION));
    QApplication::setDesktopFileName(QStringLiteral("maid-helper"));

    const QIcon icon = appIcon();
    QApplication::setWindowIcon(icon);

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("First-aid kit for small Linux breakage."));
    parser.addHelpOption();
    parser.addVersionOption();

    const QCommandLineOption checkOption(
        QStringLiteral("check"),
        QStringLiteral("Start a read-only check immediately."));
    const QCommandLineOption noCheckOption(
        QStringLiteral("no-check"),
        QStringLiteral("Open without running the automatic check."));
    const QCommandLineOption onlyOption(
        QStringLiteral("only"),
        QStringLiteral("Run one module only (for example: bluetooth)."),
        QStringLiteral("module"));
    const QCommandLineOption screenshotOption(
        QStringLiteral("screenshot"),
        QStringLiteral("Save a window screenshot and exit (testing)."),
        QStringLiteral("file"));
    parser.addOption(checkOption);
    parser.addOption(noCheckOption);
    parser.addOption(onlyOption);
    parser.addOption(screenshotOption);
    parser.process(app);

    MainWindow window;
    if (parser.isSet(onlyOption))
        window.setOnlyModule(parser.value(onlyOption));

    if (!parser.isSet(noCheckOption) || parser.isSet(checkOption))
        QTimer::singleShot(250, &window, &MainWindow::startCheck);

    if (parser.isSet(screenshotOption)) {
        const QString path = parser.value(screenshotOption);
        QTimer::singleShot(1600, &window, [&window, path] {
            window.grab().save(path);
            QApplication::quit();
        });
    }

    window.show();
    return app.exec();
}
