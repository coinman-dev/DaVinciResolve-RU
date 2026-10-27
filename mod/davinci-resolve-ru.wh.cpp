// ==WindhawkMod==
// @id              davinci-resolve-ru
// @name            DaVinci Resolve: Russian translation completion
// @description     Adds the missing Russian translations to the DaVinci Resolve interface
// @version         0.2.0
// @author          coinman-dev
// @github          https://github.com/coinman-dev
// @homepage        https://github.com/coinman-dev/DaVinciResolve-RU
// @include         Resolve.exe
// @architecture    x86-64
// ==/WindhawkMod==

// Source code is published under The GNU General Public License v3.0.

// ==WindhawkModReadme==
/*
# DaVinci Resolve: Russian translation completion

The Russian translation of DaVinci Resolve covers about 16,500 of the 29,000
interface strings. This mod loads an additional translation file with the
missing strings when Resolve uses the Russian interface language. Resolve
itself isn't modified.

The translation file comes from the
[DaVinciResolve-RU](https://github.com/coinman-dev/DaVinciResolve-RU) project.
Download `resolve_ru_extra.qm` from the latest release and set its path in the
mod settings.

Restart Resolve after enabling or disabling the mod, or after changing the
settings.
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- translationFile: '%ProgramData%\DaVinciResolve-RU\resolve_ru_extra.qm'
  $name: Translation file
  $description: >-
    Path to resolve_ru_extra.qm. Environment variables are expanded.
- logUntranslated: false
  $name: Log untranslated strings
  $description: >-
    Write the strings Resolve shows untranslated to the mod log, once each, for
    completing the translation. Enable mod logging to see them.
*/
// ==/WindhawkModSettings==

#include <windhawk_utils.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

// Qt 5 types, only used through pointers and the exported functions of
// Qt5Core.dll.
struct QTranslator;
struct QObject;

// QArrayData, the header of the QString data.
struct QArrayData {
    int ref;
    int size;
    unsigned int alloc;
    ptrdiff_t offset;
};

struct QString {
    QArrayData* d;
};

using QTranslator_ctor_t = QTranslator*(__cdecl*)(QTranslator* pThis,
                                                  QObject* parent);
using QTranslator_loadData_t = bool(__cdecl*)(QTranslator* pThis,
                                              const unsigned char* data,
                                              int len,
                                              const QString* directory);
using QTranslator_translate_t = QString*(__cdecl*)(const QTranslator* pThis,
                                                   QString* result,
                                                   const char* context,
                                                   const char* sourceText,
                                                   const char* disambiguation,
                                                   int n);
using QCoreApplication_installTranslator_t =
    bool(__cdecl*)(QTranslator* translationFile);
using QCoreApplication_removeTranslator_t =
    bool(__cdecl*)(QTranslator* translationFile);
using QCoreApplication_translate_t = QString*(__cdecl*)(QString* result,
                                                        const char* context,
                                                        const char* sourceText,
                                                        const char* disambiguation,
                                                        int n);

QTranslator_ctor_t QTranslator_ctor;
QTranslator_loadData_t QTranslator_loadData;
QTranslator_translate_t QTranslator_translate;
QCoreApplication_installTranslator_t QCoreApplication_installTranslator_Original;
QCoreApplication_removeTranslator_t QCoreApplication_removeTranslator;
QCoreApplication_translate_t QCoreApplication_translate_Original;
const QArrayData* g_sharedNull;

// Strings translated by the Russian translation of Resolve, to tell it apart
// from the other languages.
constexpr struct {
    const char* context;
    const char* sourceText;
} kRussianProbes[] = {
    {"ActionDefinitions", "Undo"},
    {"ActionDefinitions", "Redo"},
    {"ActionDefinitions", "Save Project"},
};

std::vector<unsigned char> g_translationData;
QTranslator* g_translator;
std::atomic<bool> g_installing;

bool StringHasCyrillic(const QString& string) {
    const QArrayData* d = string.d;
    if (!d || d->size <= 0) {
        return false;
    }

    auto chars = reinterpret_cast<const char16_t*>(
        reinterpret_cast<const char*>(d) + d->offset);
    for (int i = 0; i < d->size; i++) {
        if (chars[i] >= 0x0400 && chars[i] <= 0x04FF) {
            return true;
        }
    }

    return false;
}

bool IsRussianTranslator(QTranslator* translator) {
    for (const auto& probe : kRussianProbes) {
        // The result isn't released, a few bytes per installed translator.
        QString result{};
        QTranslator_translate(translator, &result, probe.context,
                              probe.sourceText, nullptr, -1);
        if (StringHasCyrillic(result)) {
            return true;
        }
    }

    return false;
}

bool LoadTranslationFile() {
    PCWSTR setting = Wh_GetStringSetting(L"translationFile");
    WCHAR path[MAX_PATH * 2];
    DWORD length = ExpandEnvironmentStrings(setting, path, ARRAYSIZE(path));
    Wh_FreeStringSetting(setting);
    if (!length || length > ARRAYSIZE(path)) {
        Wh_Log(L"Failed to expand the translation file path");
        return false;
    }

    HANDLE file = CreateFile(path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                             OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        Wh_Log(L"Failed to open %s: %u", path, GetLastError());
        return false;
    }

    LARGE_INTEGER size;
    bool ok = GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
              size.QuadPart < 64 * 1024 * 1024;
    if (ok) {
        g_translationData.resize(static_cast<size_t>(size.QuadPart));
        DWORD read = 0;
        ok = ReadFile(file, g_translationData.data(),
                      static_cast<DWORD>(g_translationData.size()), &read,
                      nullptr) &&
             read == g_translationData.size();
    }
    CloseHandle(file);

    if (!ok) {
        Wh_Log(L"Failed to read %s", path);
        g_translationData.clear();
        return false;
    }

    Wh_Log(L"Loaded %s, %zu bytes", path, g_translationData.size());
    return true;
}

// Installs the additional translator in front of the Russian one, so that it
// is searched first. It only has the strings the Russian one lacks.
void InstallAdditionalTranslator() {
    if (!g_translator) {
        if (g_translationData.empty() && !LoadTranslationFile()) {
            return;
        }

        // QTranslator only has the QObject members, two pointers.
        auto translator =
            static_cast<QTranslator*>(HeapAlloc(GetProcessHeap(),
                                                HEAP_ZERO_MEMORY, 64));
        QTranslator_ctor(translator, nullptr);

        QString directory{const_cast<QArrayData*>(g_sharedNull)};
        if (!QTranslator_loadData(translator, g_translationData.data(),
                                  static_cast<int>(g_translationData.size()),
                                  &directory)) {
            Wh_Log(L"QTranslator::load failed");
            return;
        }

        g_translator = translator;
    } else {
        QCoreApplication_removeTranslator(g_translator);
    }

    g_installing = true;
    QCoreApplication_installTranslator_Original(g_translator);
    g_installing = false;

    Wh_Log(L"Installed the additional translator");
}

bool __cdecl QCoreApplication_installTranslator_Hook(
    QTranslator* translationFile) {
    bool ret = QCoreApplication_installTranslator_Original(translationFile);

    if (ret && !g_installing && translationFile &&
        translationFile != g_translator) {
        bool russian = IsRussianTranslator(translationFile);
        Wh_Log(L"Translator %p installed, Russian: %d", translationFile,
               russian);
        if (russian) {
            InstallAdditionalTranslator();
        }
    }

    return ret;
}

// The result is the source text when no translator has the string.
bool IsSourceText(const QString& result, const char* sourceText) {
    const QArrayData* d = result.d;
    size_t length = strlen(sourceText);
    if (!d || static_cast<size_t>(d->size) != length) {
        return false;
    }

    auto chars = reinterpret_cast<const char16_t*>(
        reinterpret_cast<const char*>(d) + d->offset);
    for (size_t i = 0; i < length; i++) {
        if (chars[i] != static_cast<unsigned char>(sourceText[i])) {
            return false;
        }
    }

    return true;
}

std::mutex g_untranslatedMutex;
std::unordered_set<std::string> g_untranslated;

QString* __cdecl QCoreApplication_translate_Hook(QString* result,
                                                 const char* context,
                                                 const char* sourceText,
                                                 const char* disambiguation,
                                                 int n) {
    QCoreApplication_translate_Original(result, context, sourceText,
                                        disambiguation, n);

    // Only strings with letters, and only while a Russian translator is in
    // use, which is when the additional one is installed.
    if (g_translator && context && sourceText &&
        IsSourceText(*result, sourceText)) {
        bool hasLetters = false;
        for (const char* p = sourceText; *p; p++) {
            if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
                hasLetters = true;
                break;
            }
        }

        if (hasLetters) {
            std::string key = std::string(context) + '\x04' + sourceText;
            std::lock_guard<std::mutex> lock(g_untranslatedMutex);
            if (g_untranslated.insert(key).second) {
                Wh_Log(L"Untranslated: %S | %S", context, sourceText);
            }
        }
    }

    return result;
}

BOOL Wh_ModInit() {
    Wh_Log(L">");

    // Resolve.exe imports Qt5Core.dll, which is next to it.
    WCHAR qtCorePath[MAX_PATH];
    DWORD length = GetModuleFileName(nullptr, qtCorePath, ARRAYSIZE(qtCorePath));
    if (!length || length == ARRAYSIZE(qtCorePath)) {
        return FALSE;
    }
    PWSTR fileName = wcsrchr(qtCorePath, L'\\');
    if (!fileName) {
        return FALSE;
    }
    wcscpy_s(fileName + 1, ARRAYSIZE(qtCorePath) - (fileName + 1 - qtCorePath),
             L"Qt5Core.dll");

    HMODULE qtCore = LoadLibraryEx(qtCorePath, nullptr,
                                   LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!qtCore) {
        Wh_Log(L"Failed to load %s", qtCorePath);
        return FALSE;
    }

    QTranslator_ctor = reinterpret_cast<QTranslator_ctor_t>(
        GetProcAddress(qtCore, "??0QTranslator@@QEAA@PEAVQObject@@@Z"));
    QTranslator_loadData = reinterpret_cast<QTranslator_loadData_t>(
        GetProcAddress(qtCore, "?load@QTranslator@@QEAA_NPEBEHAEBVQString@@@Z"));
    QTranslator_translate = reinterpret_cast<QTranslator_translate_t>(
        GetProcAddress(qtCore,
                       "?translate@QTranslator@@UEBA?AVQString@@PEBD00H@Z"));
    QCoreApplication_removeTranslator =
        reinterpret_cast<QCoreApplication_removeTranslator_t>(GetProcAddress(
            qtCore,
            "?removeTranslator@QCoreApplication@@SA_NPEAVQTranslator@@@Z"));
    g_sharedNull = reinterpret_cast<const QArrayData*>(
        GetProcAddress(qtCore, "?shared_null@QArrayData@@2QBU1@B"));
    auto installTranslator =
        reinterpret_cast<QCoreApplication_installTranslator_t>(GetProcAddress(
            qtCore,
            "?installTranslator@QCoreApplication@@SA_NPEAVQTranslator@@@Z"));

    if (!QTranslator_ctor || !QTranslator_loadData || !QTranslator_translate ||
        !QCoreApplication_removeTranslator || !g_sharedNull ||
        !installTranslator) {
        Wh_Log(L"Missing Qt5Core.dll exports");
        return FALSE;
    }

    WindhawkUtils::SetFunctionHook(installTranslator,
                                   QCoreApplication_installTranslator_Hook,
                                   &QCoreApplication_installTranslator_Original);

    if (Wh_GetIntSetting(L"logUntranslated")) {
        auto translate = reinterpret_cast<QCoreApplication_translate_t>(
            GetProcAddress(
                qtCore,
                "?translate@QCoreApplication@@SA?AVQString@@PEBD00H@Z"));
        if (translate) {
            WindhawkUtils::SetFunctionHook(translate,
                                           QCoreApplication_translate_Hook,
                                           &QCoreApplication_translate_Original);
        }
    }

    return TRUE;
}

void Wh_ModUninit() {
    Wh_Log(L">");

    // The translator stays installed until Resolve is restarted. Removing it
    // from this thread isn't safe, so it and its data are kept alive.
    if (g_translator) {
        new std::vector<unsigned char>(std::move(g_translationData));
    }
}
