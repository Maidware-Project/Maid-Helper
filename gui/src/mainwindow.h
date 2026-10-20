#pragma once

#include <QByteArray>
#include <QHash>
#include <QMainWindow>
#include <QProcess>
#include <QSettings>
#include <QString>

class QAction;
class QCheckBox;
class QCloseEvent;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPlainTextEdit;
class QProgressBar;
class QPushButton;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

    void setOnlyModule(const QString &key);

public slots:
    void startCheck();
    void startFix();
    void startReport();

protected:
    void closeEvent(QCloseEvent *event) override;

private slots:
    void cancelRun();
    void openLog();
    void showAbout();
    void quitRequested();
    void readCheckOutput();
    void checkFinished(int exitCode, QProcess::ExitStatus status);
    void checkFailed(QProcess::ProcessError error);
    void readFixOutput();
    void fixFinished(int exitCode, QProcess::ExitStatus status);
    void fixFailed(QProcess::ProcessError error);
    void readReportOutput();
    void reportFinished(int exitCode, QProcess::ExitStatus status);
    void reportFailed(QProcess::ProcessError error);
    void moduleSelected(QListWidgetItem *current, QListWidgetItem *previous);

private:
    void buildUi();
    void buildMenus();
    void findTools();
    bool ensureAskpass();
    bool ensureSudoShim();
    void setBusy(bool busy);
    void setStatus(const QString &title, const QString &detail, const QString &iconName);
    void appendOutput(const QString &text);
    void parseSections();
    void updateModuleIcons(int exitCode);
    void showModule(const QString &key);
    void refreshOutput();
    void showError(const QString &title, const QString &message);

    QProcess *m_check = nullptr;
    QProcess *m_fix = nullptr;
    QProcess *m_report = nullptr;
    QByteArray m_checkBuffer;
    QByteArray m_fixBuffer;
    QByteArray m_reportBuffer;
    bool m_checkCancelled = false;
    bool m_fixing = false;
    bool m_reporting = false;
    bool m_busy = false;
    bool m_canFix = false;
    bool m_recheckAfterFix = false;

    QString m_onlyModule;
    QString m_helper;
    QString m_askpassPath;
    QString m_sudoShimDir;
    QString m_logPath;
    QString m_lastReportPath;
    QString m_fullOutput;
    QHash<QString, QString> m_sections;

    QLabel *m_titleLabel = nullptr;
    QLabel *m_subtitleLabel = nullptr;
    QLabel *m_statusIcon = nullptr;
    QLabel *m_statusTitle = nullptr;
    QLabel *m_statusDetail = nullptr;
    QLabel *m_lastRun = nullptr;
    QLabel *m_systemInfo = nullptr;
    QLabel *m_footer = nullptr;

    QListWidget *m_modules = nullptr;
    QPlainTextEdit *m_output = nullptr;
    QPushButton *m_checkButton = nullptr;
    QPushButton *m_fixButton = nullptr;
    QPushButton *m_cancelButton = nullptr;
    QPushButton *m_reportButton = nullptr;
    QPushButton *m_logButton = nullptr;
    QCheckBox *m_msfonts = nullptr;
    QProgressBar *m_progress = nullptr;

    QAction *m_menuCheckAction = nullptr;
    QAction *m_menuFixAction = nullptr;
    QAction *m_menuLogAction = nullptr;

    QSettings m_settings;
};
