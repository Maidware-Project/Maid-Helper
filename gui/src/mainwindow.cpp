#include "mainwindow.h"

#include <QAction>
#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QFrame>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QIcon>
#include <QKeySequence>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProcessEnvironment>
#include <QProgressBar>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollBar>
#include <QSplitter>
#include <QStandardPaths>
#include <QStatusBar>
#include <QStyle>
#include <QSysInfo>
#include <QTextCursor>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>

namespace {
constexpr int kStatusIconSize = 40;

struct ModuleInfo {
    const char *key;
    const char *label;
};

const ModuleInfo kModules[] = {
    {"codecs", "Codecs"},
    {"gpu", "Graphics drivers"},
    {"print", "Printing"},
    {"fonts", "Fonts"},
    {"suite", "Maid suite"},
    {"gamepad", "Gamepads"},
    {"flatpak", "Flatpak"},
    {"firmware", "Firmware"},
    {"kdeconnect", "KDE Connect"},
};

QString cleanPath(const QString &path)
{
    if (path.isEmpty())
        return QString();
    const QFileInfo info(path);
    const QString canonical = info.canonicalFilePath();
    return canonical.isEmpty() ? info.absoluteFilePath() : canonical;
}

QIcon statusIcon(const QString &kind)
{
    QIcon icon;
    QStyle::StandardPixmap fallback = QStyle::SP_MessageBoxQuestion;
    if (kind == QLatin1String("ok")) {
        icon = QIcon::fromTheme(QStringLiteral("emblem-default"));
        fallback = QStyle::SP_DialogApplyButton;
    } else if (kind == QLatin1String("warning")) {
        icon = QIcon::fromTheme(QStringLiteral("dialog-warning"));
        fallback = QStyle::SP_MessageBoxWarning;
    } else if (kind == QLatin1String("error")) {
        icon = QIcon::fromTheme(QStringLiteral("dialog-error"));
        fallback = QStyle::SP_MessageBoxCritical;
    } else {
        icon = QIcon::fromTheme(QStringLiteral("dialog-information"));
    }
    if (icon.isNull())
        icon = QApplication::style()->standardIcon(fallback);
    return icon;
}

QString moduleLabel(const QString &key)
{
    for (const ModuleInfo &info : kModules) {
        if (key == QLatin1String(info.key))
            return QString::fromLatin1(info.label);
    }
    return key;
}
}

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
    , m_settings()
{
    setWindowTitle(QStringLiteral("Maid Helper"));
    findTools();
    ensureAskpass();
    ensureSudoShim();
    buildUi();
    buildMenus();

    if (m_helper.isEmpty()) {
        setStatus(QStringLiteral("Helper not found"),
                  QStringLiteral("maid-helper was not found next to this app or in ~/.local/bin. Run install.sh first."),
                  QStringLiteral("dialog-error"));
    }

    if (m_settings.contains(QStringLiteral("window/geometry")))
        restoreGeometry(m_settings.value(QStringLiteral("window/geometry")).toByteArray());

    const QFileInfo logInfo(m_logPath);
    if (logInfo.exists()) {
        m_lastRun->setText(QStringLiteral("Last run: ")
                           + logInfo.lastModified().toString(QStringLiteral("yyyy-MM-dd HH:mm")));
    } else {
        m_lastRun->setText(QStringLiteral("No check has run yet."));
    }
}

MainWindow::~MainWindow()
{
    m_settings.setValue(QStringLiteral("window/geometry"), saveGeometry());
    m_settings.sync();
}

void MainWindow::setOnlyModule(const QString &key)
{
    m_onlyModule = key;
    const bool bluetooth = (key == QLatin1String("bluetooth"));

    if (bluetooth) {
        setWindowTitle(QStringLiteral("Maid BT Helper"));
        if (m_titleLabel)
            m_titleLabel->setText(QStringLiteral("Maid BT Helper"));
        if (m_subtitleLabel) {
            m_subtitleLabel->setText(QStringLiteral(
                "Bluetooth first aid for Maid BT: adapter, earbuds, fallback speaker, services, sound quality, and a shareable report."));
        }
        if (m_checkButton)
            m_checkButton->setText(QStringLiteral("Check Bluetooth"));
        if (m_fixButton)
            m_fixButton->setText(QStringLiteral("Fix Bluetooth issues"));
        if (m_reportButton)
            m_reportButton->setVisible(true);
    } else if (!key.isEmpty()) {
        setWindowTitle(QStringLiteral("Maid Helper - ") + moduleLabel(key));
    }

    if (!m_modules)
        return;

    QListWidgetItem *selected = m_modules->item(0);
    for (int i = 1; i < m_modules->count(); ++i) {
        QListWidgetItem *item = m_modules->item(i);
        const bool match = key.isEmpty() || item->data(Qt::UserRole).toString() == key;
        item->setHidden(!match);
        if (match)
            selected = item;
    }
    m_modules->setCurrentItem(selected);
}

void MainWindow::findTools()
{
    const QString override = qEnvironmentVariable("MAID_HELPER_BIN");
    if (!override.isEmpty() && QFileInfo(override).isExecutable()) {
        m_helper = cleanPath(override);
    } else {
        const QString appDir = QCoreApplication::applicationDirPath();
        const QStringList candidates = {
            appDir + QStringLiteral("/maid-helper"),
            QDir(appDir).filePath(QStringLiteral("../bin/maid-helper")),
            QDir(appDir).filePath(QStringLiteral("../../bin/maid-helper")),
            QDir::homePath() + QStringLiteral("/.local/bin/maid-helper"),
            QStringLiteral("/usr/bin/maid-helper"),
        };
        for (const QString &candidate : candidates) {
            if (QFileInfo(candidate).isExecutable()) {
                m_helper = cleanPath(candidate);
                break;
            }
        }
        if (m_helper.isEmpty())
            m_helper = cleanPath(QStandardPaths::findExecutable(QStringLiteral("maid-helper")));
    }

    m_logPath = qEnvironmentVariable("MAID_HELPER_LOG");
    if (m_logPath.isEmpty()) {
        m_logPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/maid-helper.log");
    }
}

bool MainWindow::ensureAskpass()
{
    QString helper = QStandardPaths::findExecutable(QStringLiteral("ksshaskpass"));
    if (helper.isEmpty())
        helper = QStandardPaths::findExecutable(QStringLiteral("ssh-askpass"));

    if (!helper.isEmpty()) {
        m_askpassPath = helper;
        return true;
    }

    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (!QDir().mkpath(cacheDir))
        return false;

    const QString wrapper = cacheDir + QStringLiteral("/askpass.sh");
    QFile file(wrapper);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    QString program = QCoreApplication::applicationFilePath();
    program.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    program.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    file.write("#!/bin/sh\nexec \"" + program.toUtf8() + "\" --askpass \"$@\"\n");
    file.close();
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner
                        | QFileDevice::ExeOwner);
    m_askpassPath = wrapper;
    return true;
}

bool MainWindow::ensureSudoShim()
{
    const QString sudo = QStandardPaths::findExecutable(QStringLiteral("sudo"));
    if (sudo.isEmpty())
        return true; // root/unsupported environment: nothing to wrap

    const QString shimDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/sudo-shim");
    if (!QDir().mkpath(shimDir))
        return false;

    const QString shim = shimDir + QStringLiteral("/sudo");
    QFile file(shim);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    QString real = sudo;
    real.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    real.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    file.write("#!/bin/sh\nexec \"" + real.toUtf8() + "\" -A \"$@\"\n");
    file.close();
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner
                        | QFileDevice::ExeOwner);
    m_sudoShimDir = shimDir;
    return true;
}

void MainWindow::buildUi()
{
    auto *central = new QWidget(this);
    setCentralWidget(central);

    auto *outer = new QVBoxLayout(central);
    outer->setContentsMargins(24, 22, 24, 18);
    outer->setSpacing(14);

    auto *title = new QLabel(QStringLiteral("Maid Helper"), central);
    QFont titleFont = title->font();
    titleFont.setPointSize(titleFont.pointSize() + 10);
    titleFont.setBold(true);
    title->setFont(titleFont);
    m_titleLabel = title;

    auto *subtitle = new QLabel(
        QStringLiteral("First aid for small Linux breakage: codecs, graphics, printing, fonts, gamepads, Flatpak, firmware, and KDE Connect. Checks are read-only; fixes only do the safe parts."),
        central);
    subtitle->setWordWrap(true);
    subtitle->setForegroundRole(QPalette::PlaceholderText);
    m_subtitleLabel = subtitle;

    outer->addWidget(title);
    outer->addWidget(subtitle);

    auto *card = new QFrame(central);
    card->setObjectName(QStringLiteral("statusCard"));
    card->setFrameShape(QFrame::StyledPanel);
    auto *cardLayout = new QHBoxLayout(card);
    cardLayout->setContentsMargins(18, 16, 18, 16);
    cardLayout->setSpacing(16);

    m_statusIcon = new QLabel(card);
    m_statusIcon->setFixedSize(kStatusIconSize, kStatusIconSize);
    m_statusIcon->setAlignment(Qt::AlignTop | Qt::AlignHCenter);
    cardLayout->addWidget(m_statusIcon);

    auto *textColumn = new QVBoxLayout;
    textColumn->setSpacing(4);
    m_statusTitle = new QLabel(card);
    QFont statusFont = m_statusTitle->font();
    statusFont.setPointSize(statusFont.pointSize() + 5);
    statusFont.setBold(true);
    m_statusTitle->setFont(statusFont);
    m_statusDetail = new QLabel(card);
    m_statusDetail->setWordWrap(true);
    m_lastRun = new QLabel(card);
    m_lastRun->setForegroundRole(QPalette::PlaceholderText);

    textColumn->addWidget(m_statusTitle);
    textColumn->addWidget(m_statusDetail);
    textColumn->addSpacing(4);
    textColumn->addWidget(m_lastRun);
    cardLayout->addLayout(textColumn, 1);
    outer->addWidget(card);

    auto *splitter = new QSplitter(Qt::Horizontal, central);
    splitter->setChildrenCollapsible(false);

    auto *sidebar = new QFrame(splitter);
    sidebar->setFrameShape(QFrame::StyledPanel);
    auto *sidebarLayout = new QVBoxLayout(sidebar);
    sidebarLayout->setContentsMargins(12, 12, 12, 12);
    auto *sidebarTitle = new QLabel(QStringLiteral("Modules"), sidebar);
    QFont sidebarFont = sidebarTitle->font();
    sidebarFont.setBold(true);
    sidebarTitle->setFont(sidebarFont);
    sidebarLayout->addWidget(sidebarTitle);

    m_modules = new QListWidget(sidebar);
    m_modules->setFrameShape(QFrame::NoFrame);
    m_modules->setIconSize(QSize(16, 16));
    m_modules->setMinimumWidth(200);
    sidebarLayout->addWidget(m_modules, 1);

    auto *allItem = new QListWidgetItem(statusIcon(QStringLiteral("unknown")),
                                        QStringLiteral("All modules"), m_modules);
    allItem->setData(Qt::UserRole, QStringLiteral("all"));
    allItem->setToolTip(QStringLiteral("Show the complete report."));
    for (const ModuleInfo &info : kModules) {
        auto *item = new QListWidgetItem(statusIcon(QStringLiteral("unknown")),
                                         QString::fromLatin1(info.label), m_modules);
        item->setData(Qt::UserRole, QString::fromLatin1(info.key));
        item->setToolTip(QStringLiteral("Not checked yet."));
    }
    m_modules->setCurrentRow(0);

    auto *details = new QGroupBox(QStringLiteral("Report"), splitter);
    auto *detailsLayout = new QVBoxLayout(details);
    detailsLayout->setContentsMargins(10, 12, 10, 10);
    m_output = new QPlainTextEdit(details);
    m_output->setReadOnly(true);
    m_output->setLineWrapMode(QPlainTextEdit::NoWrap);
    m_output->setMaximumBlockCount(12000);
    m_output->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    m_output->setPlaceholderText(QStringLiteral("The report appears here. Select a module on the left to focus its section."));
    detailsLayout->addWidget(m_output);

    splitter->addWidget(sidebar);
    splitter->addWidget(details);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);
    splitter->setSizes({230, 720});
    outer->addWidget(splitter, 1);

    auto *buttons = new QHBoxLayout;
    buttons->setSpacing(8);
    m_checkButton = new QPushButton(statusIcon(QStringLiteral("unknown")),
                                    QStringLiteral("Check again"), central);
    m_checkButton->setDefault(true);
    m_fixButton = new QPushButton(QIcon::fromTheme(QStringLiteral("tools-wizard")),
                                  QStringLiteral("Apply safe fixes"), central);
    m_fixButton->setEnabled(false);
    m_cancelButton = new QPushButton(QStringLiteral("Cancel"), central);
    m_cancelButton->setVisible(false);
    m_reportButton = new QPushButton(QIcon::fromTheme(QStringLiteral("document-save")),
                                     QStringLiteral("Save support report"), central);
    m_reportButton->setVisible(false);
    m_reportButton->setToolTip(QStringLiteral(
        "Write a Bluetooth support report with the check result and recent logs. "
        "MAC addresses, your home path, and the host name are redacted."));
    m_logButton = new QPushButton(QIcon::fromTheme(QStringLiteral("text-x-generic")),
                                  QStringLiteral("Open log"), central);
    m_msfonts = new QCheckBox(QStringLiteral("Allow MS fonts (non-free)"), central);
    m_msfonts->setToolTip(QStringLiteral(
        "Only needed for the optional Microsoft core fonts. They are non-free and show a EULA. "
        "Leave this off to skip them."));

    buttons->addWidget(m_checkButton);
    buttons->addWidget(m_fixButton);
    buttons->addWidget(m_cancelButton);
    buttons->addWidget(m_reportButton);
    buttons->addStretch(1);
    buttons->addWidget(m_msfonts);
    buttons->addWidget(m_logButton);
    outer->addLayout(buttons);

    m_progress = new QProgressBar(central);
    m_progress->setRange(0, 0);
    m_progress->setTextVisible(false);
    m_progress->setVisible(false);
    outer->addWidget(m_progress);

    auto *footer = new QHBoxLayout;
    m_systemInfo = new QLabel(QSysInfo::prettyProductName(), central);
    m_systemInfo->setForegroundRole(QPalette::PlaceholderText);
    m_footer = new QLabel(central);
    m_footer->setTextFormat(Qt::PlainText);
    m_footer->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_footer->setForegroundRole(QPalette::PlaceholderText);
    m_footer->setText(QStringLiteral("Log: ") + m_logPath);
    m_footer->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    footer->addWidget(m_systemInfo);
    footer->addStretch(1);
    footer->addWidget(m_footer);
    outer->addLayout(footer);

    connect(m_checkButton, &QPushButton::clicked, this, &MainWindow::startCheck);
    connect(m_fixButton, &QPushButton::clicked, this, &MainWindow::startFix);
    connect(m_cancelButton, &QPushButton::clicked, this, &MainWindow::cancelRun);
    connect(m_reportButton, &QPushButton::clicked, this, &MainWindow::startReport);
    connect(m_logButton, &QPushButton::clicked, this, &MainWindow::openLog);
    connect(m_modules, &QListWidget::currentItemChanged,
            this, &MainWindow::moduleSelected);

    setStatus(QStringLiteral("Ready to check"),
              QStringLiteral("The check only reads the system and explains what it finds. It never changes anything."),
              QStringLiteral("dialog-information"));

    resize(980, 720);
    setMinimumSize(760, 560);
    setBusy(false);
}

void MainWindow::buildMenus()
{
    auto *fileMenu = menuBar()->addMenu(QStringLiteral("&File"));
    m_menuCheckAction = fileMenu->addAction(QIcon::fromTheme(QStringLiteral("view-refresh")),
                                            QStringLiteral("&Check again"));
    m_menuCheckAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+R")));
    connect(m_menuCheckAction, &QAction::triggered, this, &MainWindow::startCheck);

    m_menuFixAction = fileMenu->addAction(QIcon::fromTheme(QStringLiteral("tools-wizard")),
                                          QStringLiteral("Apply safe &fixes"));
    m_menuFixAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+F")));
    m_menuFixAction->setEnabled(false);
    connect(m_menuFixAction, &QAction::triggered, this, &MainWindow::startFix);

    m_menuLogAction = fileMenu->addAction(QIcon::fromTheme(QStringLiteral("text-x-generic")),
                                          QStringLiteral("Open &log"));
    m_menuLogAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+L")));
    connect(m_menuLogAction, &QAction::triggered, this, &MainWindow::openLog);

    fileMenu->addSeparator();
    auto *quitAction = fileMenu->addAction(QStringLiteral("&Quit"));
    quitAction->setShortcut(QKeySequence::Quit);
    connect(quitAction, &QAction::triggered, this, &MainWindow::quitRequested);

    auto *helpMenu = menuBar()->addMenu(QStringLiteral("&Help"));
    auto *aboutAction = helpMenu->addAction(QStringLiteral("&About Maid Helper"));
    connect(aboutAction, &QAction::triggered, this, &MainWindow::showAbout);
}

void MainWindow::setBusy(bool busy)
{
    m_busy = busy;
    m_checkButton->setEnabled(!busy);
    m_fixButton->setEnabled(!busy && !m_fixing && m_canFix);
    m_reportButton->setEnabled(!busy);
    m_cancelButton->setVisible(busy && !m_fixing && !m_reporting);
    m_cancelButton->setEnabled(busy && !m_fixing && !m_reporting);
    m_msfonts->setEnabled(!busy);
    m_modules->setEnabled(!busy);
    m_progress->setVisible(busy);
    if (m_menuCheckAction)
        m_menuCheckAction->setEnabled(!busy);
    if (m_menuFixAction)
        m_menuFixAction->setEnabled(!busy && !m_fixing && m_canFix);
    statusBar()->showMessage(busy ? (m_fixing ? QStringLiteral("Applying fixes...")
                                             : m_reporting ? QStringLiteral("Writing report...")
                                                           : QStringLiteral("Checking..."))
                                 : QStringLiteral("Ready"));
}

void MainWindow::setStatus(const QString &title, const QString &detail,
                           const QString &iconName)
{
    m_statusTitle->setText(title);
    m_statusDetail->setText(detail);

    QString kind = QStringLiteral("unknown");
    if (iconName.contains(QStringLiteral("error")))
        kind = QStringLiteral("error");
    else if (iconName.contains(QStringLiteral("warning")))
        kind = QStringLiteral("warning");
    else if (iconName.contains(QStringLiteral("emblem-default")))
        kind = QStringLiteral("ok");
    m_statusIcon->setPixmap(statusIcon(kind).pixmap(kStatusIconSize, kStatusIconSize));
}

void MainWindow::appendOutput(const QString &text)
{
    if (text.isEmpty())
        return;
    QTextCursor cursor(m_output->document());
    cursor.movePosition(QTextCursor::End);
    cursor.insertText(text);
    m_output->verticalScrollBar()->setValue(m_output->verticalScrollBar()->maximum());
}

void MainWindow::startCheck()
{
    if (m_busy)
        return;

    if (m_helper.isEmpty()) {
        showError(QStringLiteral("Helper not found"),
                  QStringLiteral("maid-helper was not found next to this app or in ~/.local/bin. Run install.sh first."));
        return;
    }

    m_checkCancelled = false;
    m_canFix = false;
    m_recheckAfterFix = false;
    m_checkBuffer.clear();
    m_fullOutput.clear();
    m_sections.clear();
    m_output->clear();
    m_modules->setCurrentRow(0);
    for (int i = 1; i < m_modules->count(); ++i) {
        m_modules->item(i)->setIcon(statusIcon(QStringLiteral("unknown")));
        m_modules->item(i)->setToolTip(QStringLiteral("Checking..."));
    }

    appendOutput(QStringLiteral("Running: %1 --check\n\n").arg(m_helper));
    m_busy = true;
    m_reporting = false;
    m_fixing = false;
    setBusy(true);
    setStatus(QStringLiteral("Checking for problems..."),
              QStringLiteral("Reading the system, installed packages, services, and configuration. This is read-only."),
              QStringLiteral("view-refresh"));

    m_check = new QProcess(this);
    m_check->setProcessChannelMode(QProcess::MergedChannels);
    m_check->setWorkingDirectory(QDir::homePath());

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("MAID_HELPER_GUI"), QStringLiteral("1"));
    if (!m_sudoShimDir.isEmpty()) {
        env.insert(QStringLiteral("PATH"),
                   m_sudoShimDir + QLatin1Char(':') + env.value(QStringLiteral("PATH")));
    }
    if (!m_askpassPath.isEmpty())
        env.insert(QStringLiteral("SUDO_ASKPASS"), m_askpassPath);
    m_check->setProcessEnvironment(env);

    connect(m_check, &QProcess::readyReadStandardOutput,
            this, &MainWindow::readCheckOutput);
    connect(m_check, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MainWindow::checkFinished);
    connect(m_check, &QProcess::errorOccurred,
            this, &MainWindow::checkFailed);

    m_check->start(m_helper, QStringList{QStringLiteral("--check")}
                                 + (m_onlyModule.isEmpty()
                                        ? QStringList()
                                        : QStringList{QStringLiteral("--only=") + m_onlyModule}));
    m_check->closeWriteChannel();
}

void MainWindow::readCheckOutput()
{
    if (!m_check)
        return;
    const QByteArray chunk = m_check->readAllStandardOutput();
    if (chunk.isEmpty())
        return;
    m_checkBuffer += chunk;
    appendOutput(QString::fromLocal8Bit(chunk));
}

void MainWindow::cancelRun()
{
    if (!m_check || m_check->state() == QProcess::NotRunning)
        return;

    m_checkCancelled = true;
    m_cancelButton->setEnabled(false);
    statusBar()->showMessage(QStringLiteral("Stopping the check..."));
    m_check->terminate();
    QTimer::singleShot(1500, this, [this] {
        if (m_check && m_check->state() != QProcess::NotRunning)
            m_check->kill();
    });
}

void MainWindow::checkFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_check)
        return;

    const QByteArray tail = m_check->readAllStandardOutput();
    if (!tail.isEmpty()) {
        m_checkBuffer += tail;
        appendOutput(QString::fromLocal8Bit(tail));
    }

    m_check->deleteLater();
    m_check = nullptr;
    m_busy = false;
    m_canFix = (status == QProcess::NormalExit && exitCode == 2);

    m_fullOutput = QString::fromLocal8Bit(m_checkBuffer);
    parseSections();
    updateModuleIcons(exitCode);
    m_modules->setCurrentRow(0);
    refreshOutput();
    setBusy(false);

    if (m_checkCancelled) {
        m_canFix = false;
        setBusy(false);
        setStatus(QStringLiteral("Check cancelled"),
                  QStringLiteral("Nothing was changed. Run the check again when you are ready."),
                  QStringLiteral("dialog-information"));
        appendOutput(QStringLiteral("\n[check cancelled]\n"));
    } else if (status != QProcess::NormalExit) {
        setStatus(QStringLiteral("Check failed"),
                  QStringLiteral("The helper process did not finish normally. See the report below."),
                  QStringLiteral("dialog-error"));
        QApplication::alert(this);
    } else if (exitCode == 0) {
        setStatus(QStringLiteral("Everything looks healthy"),
                  QStringLiteral("All modules passed. Nothing needs a safe fix right now."),
                  QStringLiteral("emblem-default"));
    } else if (exitCode == 2) {
        setStatus(QStringLiteral("Some things need attention"),
                  QStringLiteral("Review the report, then apply the safe fixes. Non-free Microsoft fonts stay opt-in."),
                  QStringLiteral("dialog-warning"));
    } else {
        setStatus(QStringLiteral("Check found a problem"),
                  QStringLiteral("One or more modules could not run. Read the report or open the log for details."),
                  QStringLiteral("dialog-error"));
        QApplication::alert(this);
    }

    m_lastRun->setText(QStringLiteral("Last check: ")
                       + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm")));
    m_canFix = !m_checkCancelled && status == QProcess::NormalExit && exitCode == 2;
    setBusy(false);
}

void MainWindow::checkFailed(QProcess::ProcessError error)
{
    if (!m_check)
        return;

    if (error != QProcess::FailedToStart)
        return;

    const QString message = QStringLiteral("Could not start %1. Check that it is executable.")
                                .arg(m_helper);
    m_check->deleteLater();
    m_check = nullptr;
    m_busy = false;
    m_canFix = false;
    setBusy(false);
    appendOutput(message + QLatin1Char('\n'));
    setStatus(QStringLiteral("Check failed"), message, QStringLiteral("dialog-error"));
    showError(QStringLiteral("Check failed"), message);
}

void MainWindow::startFix()
{
    if (m_busy || m_fixing)
        return;

    if (m_helper.isEmpty()) {
        showError(QStringLiteral("Helper not found"),
                  QStringLiteral("maid-helper was not found next to this app or in ~/.local/bin. Run install.sh first."));
        return;
    }

    if (!ensureAskpass() || m_askpassPath.isEmpty()) {
        showError(QStringLiteral("No password dialog available"),
                  QStringLiteral("Maid Helper could not find or create a graphical sudo password helper. "
                                 "Install ksshaskpass or ssh-askpass, then try again."));
        return;
    }

    if (!ensureSudoShim()) {
        showError(QStringLiteral("Could not prepare the helper"),
                  QStringLiteral("Maid Helper could not create its private sudo helper in the cache directory."));
        return;
    }

    const auto answer = QMessageBox::question(
        this, QStringLiteral("Apply safe fixes"),
        QStringLiteral("This can install packages, enable services, and apply small configuration fixes. "
                       "It will not install proprietary drivers. Microsoft fonts are installed only if "
                       "you ticked the non-free box.\n\nContinue?"),
        QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
    if (answer != QMessageBox::Yes)
        return;

    m_fixing = true;
    m_reporting = false;
    m_canFix = false;
    m_fixBuffer.clear();
    m_fullOutput.clear();
    m_sections.clear();
    m_output->clear();
    appendOutput(QStringLiteral("Running: %1 --fix\n\n").arg(m_helper));
    m_busy = true;
    setBusy(true);
    setStatus(QStringLiteral("Applying safe fixes..."),
              QStringLiteral("Keep this window open. If sudo needs a password, a graphical dialog will appear."),
              QStringLiteral("system-software-update"));

    m_fix = new QProcess(this);
    m_fix->setProcessChannelMode(QProcess::MergedChannels);
    m_fix->setWorkingDirectory(QDir::homePath());

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("MAID_HELPER_GUI"), QStringLiteral("1"));
    if (!m_sudoShimDir.isEmpty()) {
        env.insert(QStringLiteral("PATH"),
                   m_sudoShimDir + QLatin1Char(':') + env.value(QStringLiteral("PATH")));
    }
    if (!m_askpassPath.isEmpty())
        env.insert(QStringLiteral("SUDO_ASKPASS"), m_askpassPath);
    if (m_msfonts->isChecked())
        env.insert(QStringLiteral("MSFONTS"), QStringLiteral("1"));
    m_fix->setProcessEnvironment(env);

    connect(m_fix, &QProcess::readyReadStandardOutput,
            this, &MainWindow::readFixOutput);
    connect(m_fix, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MainWindow::fixFinished);
    connect(m_fix, &QProcess::errorOccurred,
            this, &MainWindow::fixFailed);

    m_fix->start(m_helper, QStringList{QStringLiteral("--fix")}
                               + (m_onlyModule.isEmpty()
                                      ? QStringList()
                                      : QStringList{QStringLiteral("--only=") + m_onlyModule}));
    m_fix->closeWriteChannel();
}

void MainWindow::readFixOutput()
{
    if (!m_fix)
        return;
    const QByteArray chunk = m_fix->readAllStandardOutput();
    if (chunk.isEmpty())
        return;
    m_fixBuffer += chunk;
    appendOutput(QString::fromLocal8Bit(chunk));
}

void MainWindow::fixFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_fix)
        return;

    const QByteArray tail = m_fix->readAllStandardOutput();
    if (!tail.isEmpty()) {
        m_fixBuffer += tail;
        appendOutput(QString::fromLocal8Bit(tail));
    }

    m_fix->deleteLater();
    m_fix = nullptr;
    m_fixing = false;
    m_busy = false;
    m_canFix = false;

    m_fullOutput = QString::fromLocal8Bit(m_fixBuffer);
    parseSections();
    updateModuleIcons(exitCode);
    m_modules->setCurrentRow(0);
    refreshOutput();
    setBusy(false);

    if (status != QProcess::NormalExit) {
        setStatus(QStringLiteral("Fixes stopped"),
                  QStringLiteral("The fix process did not finish normally. Open the log to see what completed."),
                  QStringLiteral("dialog-error"));
        QApplication::alert(this);
    } else if (exitCode == 0) {
        setStatus(QStringLiteral("Fixes applied"),
                  QStringLiteral("The safe fixes finished. Run Check again to confirm the new state."),
                  QStringLiteral("emblem-default"));
    } else if (exitCode == 2) {
        setStatus(QStringLiteral("Fixes applied - some items remain"),
                  QStringLiteral("This usually means a reboot is needed or a manual step remains. Read the report; run Check again to see what is left."),
                  QStringLiteral("dialog-warning"));
    } else {
        setStatus(QStringLiteral("Some fixes failed"),
                  QStringLiteral("One or more fixes could not finish. Read the report or open the log, then try the remaining step by hand."),
                  QStringLiteral("dialog-error"));
        QApplication::alert(this);
    }

    m_lastRun->setText(QStringLiteral("Last fix: ")
                       + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm")));
}

void MainWindow::fixFailed(QProcess::ProcessError error)
{
    if (!m_fix)
        return;

    if (error != QProcess::FailedToStart)
        return;

    const QString message = QStringLiteral("Could not start %1. Check that it is executable.")
                                .arg(m_helper);
    m_fix->deleteLater();
    m_fix = nullptr;
    m_fixing = false;
    m_busy = false;
    m_canFix = false;
    setBusy(false);
    appendOutput(message + QLatin1Char('\n'));
    setStatus(QStringLiteral("Fixes failed"), message, QStringLiteral("dialog-error"));
    showError(QStringLiteral("Fixes failed"), message);
}

void MainWindow::startReport()
{
    if (m_busy)
        return;

    if (m_helper.isEmpty()) {
        showError(QStringLiteral("Helper not found"),
                  QStringLiteral("maid-helper was not found next to this app or in ~/.local/bin. Run install.sh first."));
        return;
    }

    m_reporting = true;
    m_fixing = false;
    m_canFix = false;
    m_reportBuffer.clear();
    m_output->clear();
    appendOutput(QStringLiteral("Running: %1 --report\n\n").arg(m_helper));
    m_busy = true;
    setBusy(true);
    setStatus(QStringLiteral("Writing support report..."),
              QStringLiteral("Collecting Bluetooth state, services, configuration, and recent Maid logs. "
                             "MAC addresses, your home path, and the host name are redacted."),
              QStringLiteral("dialog-information"));

    m_report = new QProcess(this);
    m_report->setProcessChannelMode(QProcess::MergedChannels);
    m_report->setWorkingDirectory(QDir::homePath());
    m_report->setProcessEnvironment(QProcessEnvironment::systemEnvironment());

    connect(m_report, &QProcess::readyReadStandardOutput,
            this, &MainWindow::readReportOutput);
    connect(m_report, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MainWindow::reportFinished);
    connect(m_report, &QProcess::errorOccurred,
            this, &MainWindow::reportFailed);

    m_report->start(m_helper, QStringList{QStringLiteral("--report")});
    m_report->closeWriteChannel();
}

void MainWindow::readReportOutput()
{
    if (!m_report)
        return;
    const QByteArray chunk = m_report->readAllStandardOutput();
    if (chunk.isEmpty())
        return;
    m_reportBuffer += chunk;
    appendOutput(QString::fromLocal8Bit(chunk));
}

void MainWindow::reportFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_report)
        return;

    const QByteArray tail = m_report->readAllStandardOutput();
    if (!tail.isEmpty()) {
        m_reportBuffer += tail;
        appendOutput(QString::fromLocal8Bit(tail));
    }

    m_report->deleteLater();
    m_report = nullptr;
    m_reporting = false;
    m_busy = false;
    setBusy(false);

    const QString output = QString::fromLocal8Bit(m_reportBuffer);
    const QRegularExpression reportLine(QStringLiteral("^REPORT: (.+)$"),
                                        QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = reportLine.match(output);

    if (status != QProcess::NormalExit) {
        setStatus(QStringLiteral("Report failed"),
                  QStringLiteral("The report process did not finish normally. See the output below."),
                  QStringLiteral("dialog-error"));
        QApplication::alert(this);
        return;
    }

    if (!match.hasMatch()) {
        if (exitCode != 0) {
            setStatus(QStringLiteral("Report failed"),
                      QStringLiteral("The helper could not write the report. See the output below."),
                      QStringLiteral("dialog-error"));
            QApplication::alert(this);
        } else {
            setStatus(QStringLiteral("Report finished"),
                      QStringLiteral("The helper did not return a report path. See the output below."),
                      QStringLiteral("dialog-information"));
        }
        return;
    }

    m_lastReportPath = match.captured(1).trimmed();
    setStatus(QStringLiteral("Support report saved"),
              QStringLiteral("Saved to %1 - MAC addresses, your home path, and the host name are redacted.")
                  .arg(m_lastReportPath),
              QStringLiteral("emblem-default"));
    m_lastRun->setText(QStringLiteral("Last report: ")
                       + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm")));

    if (QFileInfo::exists(m_lastReportPath))
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastReportPath));
}

void MainWindow::reportFailed(QProcess::ProcessError error)
{
    if (!m_report)
        return;

    if (error != QProcess::FailedToStart)
        return;

    const QString message = QStringLiteral("Could not start %1. Check that it is executable.")
                                .arg(m_helper);
    m_report->deleteLater();
    m_report = nullptr;
    m_reporting = false;
    m_busy = false;
    setBusy(false);
    appendOutput(message + QLatin1Char('\n'));
    setStatus(QStringLiteral("Report failed"), message, QStringLiteral("dialog-error"));
    showError(QStringLiteral("Report failed"), message);
}

void MainWindow::parseSections()
{
    m_sections.clear();
    const QRegularExpression heading(
        QStringLiteral("^--- ([A-Za-z0-9_-]+) ---\\s*$"),
        QRegularExpression::MultilineOption);
    QRegularExpressionMatchIterator it = heading.globalMatch(m_fullOutput);
    QVector<QRegularExpressionMatch> matches;
    while (it.hasNext())
        matches.append(it.next());

    for (int i = 0; i < matches.size(); ++i) {
        const int start = matches[i].capturedEnd();
        const int end = (i + 1 < matches.size())
            ? matches[i + 1].capturedStart()
            : m_fullOutput.size();
        m_sections.insert(matches[i].captured(1),
                          m_fullOutput.mid(start, end - start).trimmed());
    }
}

void MainWindow::updateModuleIcons(int exitCode)
{
    for (int i = 1; i < m_modules->count(); ++i) {
        QListWidgetItem *item = m_modules->item(i);
        const QString key = item->data(Qt::UserRole).toString();
        const QString section = m_sections.value(key);
        if (section.isEmpty()) {
            item->setIcon(statusIcon(QStringLiteral("unknown")));
            item->setToolTip(QStringLiteral("No output from this module."));
            continue;
        }

        QString statusKind = QStringLiteral("ok");
        QString tooltip = QStringLiteral("Healthy.");
        if (section.contains(QStringLiteral("FAILED"))) {
            statusKind = QStringLiteral("error");
            tooltip = QStringLiteral("A fix failed or the check could not complete.");
        } else if (section.contains(QStringLiteral("NEEDS FIX"))) {
            statusKind = QStringLiteral("warning");
            tooltip = QStringLiteral("Needs a safe fix.");
        }
        const QStringList lines = section.split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            if (line.contains(QStringLiteral("NEEDS FIX"))
                || line.contains(QStringLiteral("FAILED"))) {
                tooltip += QLatin1Char('\n') + line.trimmed();
                break;
            }
        }
        item->setIcon(statusIcon(statusKind));
        item->setToolTip(tooltip);
    }

    QListWidgetItem *all = m_modules->item(0);
    if (all) {
        const QString kind = exitCode == 0 ? QStringLiteral("ok")
            : exitCode == 2 ? QStringLiteral("warning")
                            : QStringLiteral("error");
        all->setIcon(statusIcon(kind));
        all->setToolTip(QStringLiteral("Complete report for every module."));
    }
}

void MainWindow::showModule(const QString &key)
{
    if (key == QLatin1String("all")) {
        m_output->setPlainText(m_fullOutput);
        return;
    }
    const QString section = m_sections.value(key);
    if (section.isEmpty()) {
        m_output->setPlainText(QStringLiteral("No output for %1 yet. Run a check first.")
                                   .arg(moduleLabel(key)));
    } else {
        m_output->setPlainText(QStringLiteral("--- %1 ---\n\n%2\n").arg(key, section));
    }
    m_output->verticalScrollBar()->setValue(0);
}

void MainWindow::moduleSelected(QListWidgetItem *current, QListWidgetItem *previous)
{
    Q_UNUSED(previous)
    if (!current || !m_output)
        return;
    showModule(current->data(Qt::UserRole).toString());
}

void MainWindow::refreshOutput()
{
    if (!m_modules || !m_output)
        return;
    const QListWidgetItem *item = m_modules->currentItem();
    showModule(item ? item->data(Qt::UserRole).toString() : QStringLiteral("all"));
}

void MainWindow::openLog()
{
    if (!QFileInfo::exists(m_logPath)) {
        QMessageBox::information(this, QStringLiteral("No log yet"),
                                 QStringLiteral("There is no log at:\n%1\n\nRun a check or fix first.")
                                     .arg(m_logPath));
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(m_logPath));
}

void MainWindow::showAbout()
{
    QMessageBox::about(
        this,
        QStringLiteral("About Maid Helper"),
        QStringLiteral(
            "<h3>Maid Helper %1</h3>"
            "<p>First aid for small Linux breakage: codecs, graphics, printing, "
            "fonts, gamepads, Flatpak, firmware, and KDE Connect.</p>"
            "<p>Checks are read-only. Fixes run inside this window; sudo uses a "
            "graphical password dialog, so no terminal is needed. The only "
            "non-free option (Microsoft fonts) stays off unless you tick it.</p>"
            "<p>MIT licensed. <a href=\"https://github.com/Maidware-Project/Maid-Helper\">"
            "github.com/Maidware-Project/Maid-Helper</a></p>")
            .arg(QStringLiteral(MAID_HELPER_VERSION)));
}

void MainWindow::showError(const QString &title, const QString &message)
{
    statusBar()->showMessage(title, 8000);
    QMessageBox::critical(this, title, message);
}

void MainWindow::quitRequested()
{
    if (m_busy) {
        QMessageBox::information(
            this, QStringLiteral("Run in progress"),
            m_fixing ? QStringLiteral("Safe fixes are still running. Let them finish before quitting.")
                     : QStringLiteral("A check is still running. Cancel it first, then quit."));
        return;
    }
    m_settings.setValue(QStringLiteral("window/geometry"), saveGeometry());
    m_settings.sync();
    qApp->quit();
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    if (m_busy) {
        QMessageBox::information(
            this, QStringLiteral("Run in progress"),
            m_fixing ? QStringLiteral("Safe fixes are still running. Keep Maid Helper open until they finish.")
                     : QStringLiteral("A check is still running. Cancel it first, then close the window."));
        event->ignore();
        return;
    }

    m_settings.setValue(QStringLiteral("window/geometry"), saveGeometry());
    m_settings.sync();
    event->accept();
}
