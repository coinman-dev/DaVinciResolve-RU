// DaVinciResolve-RU loader: the mod mod/davinci-resolve-ru.wh.cpp without
// Windhawk.
//
// Built as dxva2.dll and placed next to Resolve.exe, which imports dxva2.dll
// and so loads this file from its own folder. All the exports are forwarded to
// the system dxva2.dll (loader/dxva2.def). On load in Resolve.exe it redirects
// QCoreApplication::installTranslator of Qt5Core.dll, and when Resolve installs
// its Russian translator, installs resolve_ru_extra.qm from the same folder in
// front of it.
//
// The redirection patches the export of Qt5Core.dll, for the modules that
// resolve their imports later, and the import tables already resolved.
//
// Log: OutputDebugString, prefix [davinci-resolve-ru] (tools/dbwin.ps1).

#include <windows.h>
#include <psapi.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <wchar.h>

// Qt 5 types, only used through pointers and the exported functions of
// Qt5Core.dll.
typedef struct QTranslator QTranslator;
typedef struct QObject QObject;

// QArrayData, the header of the QString data.
typedef struct QArrayData {
    int ref;
    int size;
    unsigned int alloc;
    ptrdiff_t offset;
} QArrayData;

typedef struct QString {
    QArrayData* d;
} QString;

typedef QTranslator*(__cdecl* QTranslator_ctor_t)(QTranslator* pThis,
                                                  QObject* parent);
typedef bool(__cdecl* QTranslator_loadData_t)(QTranslator* pThis,
                                              const unsigned char* data,
                                              int len,
                                              const QString* directory);
typedef QString*(__cdecl* QTranslator_translate_t)(const QTranslator* pThis,
                                                   QString* result,
                                                   const char* context,
                                                   const char* sourceText,
                                                   const char* disambiguation,
                                                   int n);
typedef bool(__cdecl* QCoreApplication_installTranslator_t)(
    QTranslator* translationFile);
typedef bool(__cdecl* QCoreApplication_removeTranslator_t)(
    QTranslator* translationFile);

#define INSTALL_TRANSLATOR_NAME \
    "?installTranslator@QCoreApplication@@SA_NPEAVQTranslator@@@Z"

static QTranslator_ctor_t QTranslator_ctor;
static QTranslator_loadData_t QTranslator_loadData;
static QTranslator_translate_t QTranslator_translate;
static QCoreApplication_installTranslator_t
    QCoreApplication_installTranslator_Original;
static QCoreApplication_removeTranslator_t QCoreApplication_removeTranslator;
static const QArrayData* g_sharedNull;

static HMODULE g_module;
static unsigned char* g_translationData;
static DWORD g_translationSize;
static QTranslator* g_translator;
static volatile LONG g_installing;

static void Log(const wchar_t* format, ...) {
    static const wchar_t prefix[] = L"[davinci-resolve-ru] ";
    wchar_t buffer[1024];
    wcscpy_s(buffer, ARRAYSIZE(buffer), prefix);
    va_list args;
    va_start(args, format);
    _vsnwprintf_s(buffer + ARRAYSIZE(prefix) - 1,
                  ARRAYSIZE(buffer) - (ARRAYSIZE(prefix) - 1), _TRUNCATE,
                  format, args);
    va_end(args);
    OutputDebugStringW(buffer);
}

// Strings translated by the Russian translation of Resolve, to tell it apart
// from the other languages.
static const struct {
    const char* context;
    const char* sourceText;
} kRussianProbes[] = {
    {"ActionDefinitions", "Undo"},
    {"ActionDefinitions", "Redo"},
    {"ActionDefinitions", "Save Project"},
};

static bool StringHasCyrillic(const QString* string) {
    const QArrayData* d = string->d;
    if (!d || d->size <= 0) {
        return false;
    }

    const wchar_t* chars =
        (const wchar_t*)((const char*)d + d->offset);
    for (int i = 0; i < d->size; i++) {
        if (chars[i] >= 0x0400 && chars[i] <= 0x04FF) {
            return true;
        }
    }

    return false;
}

static bool IsRussianTranslator(QTranslator* translator) {
    for (size_t i = 0; i < ARRAYSIZE(kRussianProbes); i++) {
        // The result isn't released, a few bytes per installed translator.
        QString result = {0};
        QTranslator_translate(translator, &result, kRussianProbes[i].context,
                              kRussianProbes[i].sourceText, NULL, -1);
        if (StringHasCyrillic(&result)) {
            return true;
        }
    }

    return false;
}

// resolve_ru_extra.qm, next to this DLL.
static bool LoadTranslationFile(void) {
    wchar_t path[MAX_PATH * 2];
    DWORD length = GetModuleFileNameW(g_module, path, ARRAYSIZE(path));
    wchar_t* fileName = wcsrchr(path, L'\\');
    if (!length || length == ARRAYSIZE(path) || !fileName ||
        wcscpy_s(fileName + 1, ARRAYSIZE(path) - (fileName + 1 - path),
                 L"resolve_ru_extra.qm")) {
        Log(L"Failed to get the translation file path");
        return false;
    }

    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        Log(L"Failed to open %s: %u", path, GetLastError());
        return false;
    }

    LARGE_INTEGER size;
    bool ok = GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
              size.QuadPart < 64 * 1024 * 1024;
    unsigned char* data = NULL;
    if (ok) {
        data = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)size.QuadPart);
        DWORD read = 0;
        ok = data && ReadFile(file, data, (DWORD)size.QuadPart, &read, NULL) &&
             read == (DWORD)size.QuadPart;
    }
    CloseHandle(file);

    if (!ok) {
        Log(L"Failed to read %s", path);
        if (data) {
            HeapFree(GetProcessHeap(), 0, data);
        }
        return false;
    }

    g_translationData = data;
    g_translationSize = (DWORD)size.QuadPart;
    Log(L"Loaded %s, %u bytes", path, g_translationSize);
    return true;
}

// Installs the additional translator in front of the Russian one, so that it
// is searched first. It only has the strings the Russian one lacks.
static void InstallAdditionalTranslator(void) {
    if (!g_translator) {
        if (!g_translationData && !LoadTranslationFile()) {
            return;
        }

        // QTranslator only has the QObject members, two pointers.
        QTranslator* translator =
            HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 64);
        if (!translator) {
            return;
        }
        QTranslator_ctor(translator, NULL);

        QString directory = {(QArrayData*)g_sharedNull};
        if (!QTranslator_loadData(translator, g_translationData,
                                  (int)g_translationSize, &directory)) {
            Log(L"QTranslator::load failed");
            return;
        }

        g_translator = translator;
    } else {
        QCoreApplication_removeTranslator(g_translator);
    }

    g_installing = TRUE;
    QCoreApplication_installTranslator_Original(g_translator);
    g_installing = FALSE;

    Log(L"Installed the additional translator");
}

static bool __cdecl QCoreApplication_installTranslator_Hook(
    QTranslator* translationFile) {
    bool ret = QCoreApplication_installTranslator_Original(translationFile);

    if (ret && !g_installing && translationFile &&
        translationFile != g_translator) {
        bool russian = IsRussianTranslator(translationFile);
        Log(L"Translator %p installed, Russian: %d", translationFile, russian);
        if (russian) {
            InstallAdditionalTranslator();
        }
    }

    return ret;
}

static IMAGE_DATA_DIRECTORY* GetDataDirectory(HMODULE module, int index) {
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)module;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)((BYTE*)module + dos->e_lfanew);
    if (nt->OptionalHeader.NumberOfRvaAndSizes <= (DWORD)index) {
        return NULL;
    }
    return &nt->OptionalHeader.DataDirectory[index];
}

// The export address table entry of a named export, NULL if there's none.
static DWORD* FindExportEntry(HMODULE module, const char* name) {
    BYTE* base = (BYTE*)module;
    IMAGE_DATA_DIRECTORY* dir =
        GetDataDirectory(module, IMAGE_DIRECTORY_ENTRY_EXPORT);
    if (!dir || !dir->VirtualAddress) {
        return NULL;
    }

    IMAGE_EXPORT_DIRECTORY* exports =
        (IMAGE_EXPORT_DIRECTORY*)(base + dir->VirtualAddress);
    DWORD* names = (DWORD*)(base + exports->AddressOfNames);
    WORD* ordinals = (WORD*)(base + exports->AddressOfNameOrdinals);
    DWORD* functions = (DWORD*)(base + exports->AddressOfFunctions);

    // The names are sorted.
    DWORD low = 0;
    DWORD high = exports->NumberOfNames;
    while (low < high) {
        DWORD middle = low + (high - low) / 2;
        int cmp = strcmp((const char*)(base + names[middle]), name);
        if (cmp == 0) {
            return &functions[ordinals[middle]];
        }
        if (cmp < 0) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }

    return NULL;
}

static void* FindExport(HMODULE module, const char* name) {
    DWORD* entry = FindExportEntry(module, name);
    return entry ? (BYTE*)module + *entry : NULL;
}

static bool WriteProtected(void* address, const void* value, SIZE_T size) {
    DWORD oldProtect;
    if (!VirtualProtect(address, size, PAGE_READWRITE, &oldProtect)) {
        return false;
    }
    memcpy(address, value, size);
    VirtualProtect(address, size, oldProtect, &oldProtect);
    return true;
}

// The export table holds 32-bit offsets from the module, so the hook gets a
// jump stub within 2 GB after the module.
static void* AllocateStubAfter(HMODULE module, void* target) {
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)module;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)((BYTE*)module + dos->e_lfanew);
    ULONG_PTR base = (ULONG_PTR)module;
    ULONG_PTR address =
        (base + nt->OptionalHeader.SizeOfImage + 0xFFFF) & ~(ULONG_PTR)0xFFFF;

    BYTE* stub = NULL;
    for (; address < base + 0x7FFF0000; address += 0x10000) {
        stub = VirtualAlloc((void*)address, 0x1000, MEM_RESERVE | MEM_COMMIT,
                            PAGE_READWRITE);
        if (stub) {
            break;
        }
    }
    if (!stub) {
        return NULL;
    }

    // jmp qword ptr [rip+0]; dq target
    static const BYTE jump[] = {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00};
    memcpy(stub, jump, sizeof(jump));
    memcpy(stub + sizeof(jump), &target, sizeof(target));
    DWORD oldProtect;
    VirtualProtect(stub, 0x1000, PAGE_EXECUTE_READ, &oldProtect);
    FlushInstructionCache(GetCurrentProcess(), stub, 0x1000);
    return stub;
}

// Replaces the resolved imports of a function in the import table of a module.
static int PatchImports(HMODULE module, void* original, void* hook) {
    BYTE* base = (BYTE*)module;
    IMAGE_DATA_DIRECTORY* dir =
        GetDataDirectory(module, IMAGE_DIRECTORY_ENTRY_IMPORT);
    if (!dir || !dir->VirtualAddress) {
        return 0;
    }

    int patched = 0;
    for (IMAGE_IMPORT_DESCRIPTOR* desc =
             (IMAGE_IMPORT_DESCRIPTOR*)(base + dir->VirtualAddress);
         desc->Name; desc++) {
        if (_stricmp((const char*)(base + desc->Name), "Qt5Core.dll") != 0) {
            continue;
        }
        for (void** slot = (void**)(base + desc->FirstThunk); *slot; slot++) {
            if (*slot == original && WriteProtected(slot, &hook, sizeof(hook))) {
                patched++;
            }
        }
    }

    return patched;
}

static bool IsResolveProcess(void) {
    wchar_t path[MAX_PATH * 2];
    DWORD length = GetModuleFileNameW(NULL, path, ARRAYSIZE(path));
    if (!length || length == ARRAYSIZE(path)) {
        return false;
    }
    const wchar_t* fileName = wcsrchr(path, L'\\');
    return _wcsicmp(fileName ? fileName + 1 : path, L"Resolve.exe") == 0;
}

static void Init(void) {
    if (!IsResolveProcess()) {
        return;
    }

    // Resolve.exe imports Qt5Core.dll, so it's already mapped.
    HMODULE qtCore = GetModuleHandleW(L"Qt5Core.dll");
    if (!qtCore) {
        Log(L"Qt5Core.dll isn't loaded");
        return;
    }

    QTranslator_ctor = (QTranslator_ctor_t)FindExport(
        qtCore, "??0QTranslator@@QEAA@PEAVQObject@@@Z");
    QTranslator_loadData = (QTranslator_loadData_t)FindExport(
        qtCore, "?load@QTranslator@@QEAA_NPEBEHAEBVQString@@@Z");
    QTranslator_translate = (QTranslator_translate_t)FindExport(
        qtCore, "?translate@QTranslator@@UEBA?AVQString@@PEBD00H@Z");
    QCoreApplication_removeTranslator =
        (QCoreApplication_removeTranslator_t)FindExport(
            qtCore,
            "?removeTranslator@QCoreApplication@@SA_NPEAVQTranslator@@@Z");
    g_sharedNull = (const QArrayData*)FindExport(
        qtCore, "?shared_null@QArrayData@@2QBU1@B");
    DWORD* installEntry = FindExportEntry(qtCore, INSTALL_TRANSLATOR_NAME);

    if (!QTranslator_ctor || !QTranslator_loadData || !QTranslator_translate ||
        !QCoreApplication_removeTranslator || !g_sharedNull || !installEntry) {
        Log(L"Missing Qt5Core.dll exports");
        return;
    }

    QCoreApplication_installTranslator_Original =
        (QCoreApplication_installTranslator_t)((BYTE*)qtCore + *installEntry);

    void* stub = AllocateStubAfter(
        qtCore, (void*)QCoreApplication_installTranslator_Hook);
    if (!stub) {
        Log(L"Failed to allocate the jump stub");
        return;
    }

    // Modules resolving their imports from now on, and GetProcAddress.
    DWORD stubOffset = (DWORD)((BYTE*)stub - (BYTE*)qtCore);
    if (!WriteProtected(installEntry, &stubOffset, sizeof(stubOffset))) {
        Log(L"Failed to patch the Qt5Core.dll export");
        return;
    }

    // Modules with the imports already resolved.
    HMODULE modules[1024];
    DWORD needed = 0;
    int patched = 0;
    if (K32EnumProcessModules(GetCurrentProcess(), modules, sizeof(modules),
                              &needed)) {
        DWORD count = needed / sizeof(HMODULE);
        if (count > ARRAYSIZE(modules)) {
            count = ARRAYSIZE(modules);
        }
        for (DWORD i = 0; i < count; i++) {
            patched += PatchImports(
                modules[i], (void*)QCoreApplication_installTranslator_Original,
                stub);
        }
    }

    Log(L"Hooked QCoreApplication::installTranslator, %d resolved imports",
        patched);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = instance;
        DisableThreadLibraryCalls(instance);
        Init();
    }
    return TRUE;
}
