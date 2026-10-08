// comfylogin.dll: what the comfylogin patch needs from the client, so that it runs on a stock 1.12.1
// client and needs no Nampower.
//
// 1. It turns off the GlueXML signature check. A stock client stops at start-up when a glue file is
//    changed, and patch-W changes MovieFrame.xml. Turtle and OctoWoW clients ship with the check off.
// 2. It lets the login screen call C functions. The Lua VM refuses a function outside WoW.exe, and the
//    login screen gets a new Lua state each time it opens, so the functions are registered each time.
// 3. It gives the login screen five functions: read and write WTF\comfylogin.txt, encrypt a password
//    with DPAPI, test that one decrypts, and log in with one. A decrypted password never reaches Lua.
//
// Each patch is made only where the stock bytes are found. Otherwise the DLL logs and leaves that part
// alone. src/README.md has each address and how it was checked.

#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <wincrypt.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

namespace
{
    wchar_t g_dir[MAX_PATH] = {};       // the client folder, with a trailing backslash
    wchar_t g_logPath[MAX_PATH] = {};   // comfylogin.log, next to the DLL

    void Log(const char* fmt, ...)
    {
        FILE* f = nullptr;
        if (_wfopen_s(&f, g_logPath, L"a") != 0 || !f)
            return;
        SYSTEMTIME t;
        GetLocalTime(&t);
        fprintf(f, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fputc('\n', f);
        fclose(f);
    }

    intptr_t Slide()
    {
        static const intptr_t slide = reinterpret_cast<intptr_t>(GetModuleHandleW(nullptr)) - 0x00400000;
        return slide;
    }

    bool SafeCopy(uintptr_t src, void* dst, size_t n)
    {
        __try
        {
            memcpy(dst, reinterpret_cast<const void*>(src), n);
            return true;
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return false;
        }
    }

    // The bytes at a client address, -1 for a byte that may be anything.
    bool HeadMatches(uintptr_t addr, const int* head, size_t n)
    {
        unsigned char b[32] = {};
        if (n > sizeof(b) || !SafeCopy(addr + Slide(), b, n))
            return false;
        for (size_t i = 0; i < n; ++i)
            if (head[i] >= 0 && b[i] != head[i])
                return false;
        return true;
    }

#define HEAD(addr, h) HeadMatches(addr, h, sizeof(h) / sizeof(h[0]))

    bool Same(uintptr_t addr, const unsigned char* bytes, size_t n)
    {
        unsigned char b[16] = {};
        return n <= sizeof(b) && SafeCopy(addr + Slide(), b, n) && memcmp(b, bytes, n) == 0;
    }

    bool Patch(uintptr_t addr, const void* bytes, size_t n)
    {
        void* p = reinterpret_cast<void*>(addr + Slide());
        DWORD prot = 0;
        if (!VirtualProtect(p, n, PAGE_EXECUTE_READWRITE, &prot))
            return false;
        memcpy(p, bytes, n);
        VirtualProtect(p, n, prot, &prot);
        FlushInstructionCache(GetCurrentProcess(), p, n);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // 1. The GlueXML signature check

    // 0x6F10F0 checks one glue file against its signature. It returns 3 for a match, and 0, 1 or 2 for
    // no signature, a bad signature or a mismatch. The four changes send every path to "return 3". They
    // are the bytes the Turtle and OctoWoW exes have.
    struct Site
    {
        uintptr_t     addr;
        unsigned char stock[2];
        unsigned char off[2];
        size_t        n;
    };

    const Site kSignature[] = {
        { 0x6F113A, { 0x5F, 0x5E }, { 0xEB, 0x19 }, 2 },   // no signature file: jump to the return 3
        { 0x6F1158, { 0x01 },       { 0x03 },       1 },   // bad signature: return 3, not 1
        { 0x6F11A7, { 0x01 },       { 0x03 },       1 },   // signature does not verify: return 3, not 1
        { 0x6F11F0, { 0x5F, 0x5E }, { 0xEB, 0xB2 }, 2 },   // the hash compare: jump to the return 3
    };

    void SignatureOff()
    {
        int stock = 0, off = 0;
        for (const Site& s : kSignature)
        {
            if (Same(s.addr, s.stock, s.n))
                ++stock;
            else if (Same(s.addr, s.off, s.n))
                ++off;
        }
        if (off == 4)
        {
            Log("GlueXML check: already off in this exe");
            return;
        }
        if (stock != 4)
        {
            Log("GlueXML check: unknown bytes, left alone (%d stock, %d off)", stock, off);
            return;
        }
        for (const Site& s : kSignature)
            Patch(s.addr, s.off, s.n);
        Log("GlueXML check: turned off");
    }

    // ---------------------------------------------------------------------------------------------
    // 2. C functions on the login screen

    // The Lua VM, before it calls a C function: mov ecx, esi (the function); call 0x42A320. That
    // function raises "Invalid function pointer" for an address outside WoW.exe. The call becomes five
    // NOPs: it has no stack arguments, and eax is not read after it. Nampower hooks 0x42A320 itself, and
    // Turtle changed its body, so the call site is the one place that is the same in every exe.
    const uintptr_t     kCheckCall = 0x6F5DE6;
    const unsigned char kCheckStock[] = { 0x8B, 0xCE, 0xE8, 0x33, 0x45, 0xD3, 0xFF };
    const unsigned char kCheckOff[]   = { 0x8B, 0xCE, 0x90, 0x90, 0x90, 0x90, 0x90 };

    bool PointerCheckOff()
    {
        if (Same(kCheckCall, kCheckOff, sizeof(kCheckOff)))
        {
            Log("pointer check: already off");
            return true;
        }
        if (!Same(kCheckCall, kCheckStock, sizeof(kCheckStock)) ||
            !Patch(kCheckCall + 2, kCheckOff + 2, 5))
        {
            Log("pointer check: unknown bytes at 0x6F5DE6, left alone");
            return false;
        }
        Log("pointer check: turned off");
        return true;
    }

    using RegisterFn       = void(__fastcall*)(const char* name, void* fn);
    using GetTopFn         = int(__fastcall*)(void* L);
    using IsStringFn       = int(__fastcall*)(void* L, int idx);
    using ToStringFn       = const char*(__fastcall*)(void* L, int idx);
    using PushNilFn        = void(__fastcall*)(void* L);
    using PushStringFn     = void(__fastcall*)(void* L, const char* s);
    using PushBooleanFn    = void(__fastcall*)(void* L, int b);
    using ServerLoginFn    = void(__fastcall*)(const char* user, const char* password);
    using GlueFunctionsFn  = void(__stdcall*)();

    // Nampower's offsets.hpp names these. The heads were read from the stock exe and are the same in
    // the octow, octow - Copy and twow-hd exes.
    const uintptr_t kRegister    = 0x704120;   // FrameScript_RegisterFunction: into the current state
    const uintptr_t kGetTop      = 0x6F3070;
    const uintptr_t kIsString    = 0x6F3510;
    const uintptr_t kToString    = 0x6F3690;
    const uintptr_t kPushNil     = 0x6F37F0;
    const uintptr_t kPushString  = 0x6F3890;
    const uintptr_t kPushBoolean = 0x6F39F0;
    const uintptr_t kServerLogin = 0x46AFB0;   // CGlueMgr::DefaultServerLogin(user, password)

    const int kRegisterHead[]    = { 0x56, 0x57, 0x8B, 0xF9, 0xE8 };
    const int kGetTopHead[]      = { 0x8B, 0x41, 0x08, 0x2B, 0x41, 0x0C };
    const int kIsStringHead[]    = { 0xE8, 0xEB, 0xFE, 0xFF, 0xFF, 0x83, 0xF8, 0x04 };
    const int kToStringHead[]    = { 0x56, 0x57, 0x8B, 0xF9, 0xE8, 0x77, 0xFD, 0xFF, 0xFF };
    const int kPushNilHead[]     = { 0x8B, 0x41, 0x08, 0xC7, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const int kPushStringHead[]  = { 0x85, 0xD2, 0x56, 0x8B, 0xF1, 0x75, 0x06 };
    const int kPushBooleanHead[] = { 0x8B, 0x41, 0x08, 0xC7, 0x00, 0x01, 0x00, 0x00, 0x00 };
    const int kServerLoginHead[] = { 0xA1, 0xFC, 0x1D, 0xB4, 0x00, 0x85, 0xC0, 0x56, 0x8B, 0xF2 };

    bool ApiMatches()
    {
        return HEAD(kRegister, kRegisterHead) && HEAD(kGetTop, kGetTopHead) && HEAD(kIsString, kIsStringHead) &&
               HEAD(kToString, kToStringHead) && HEAD(kPushNil, kPushNilHead) &&
               HEAD(kPushString, kPushStringHead) && HEAD(kPushBoolean, kPushBooleanHead) &&
               HEAD(kServerLogin, kServerLoginHead);
    }

    template <typename T> T At(uintptr_t addr) { return reinterpret_cast<T>(addr + Slide()); }

    int GetTop(void* L) { return At<GetTopFn>(kGetTop)(L); }
    void PushNil(void* L) { At<PushNilFn>(kPushNil)(L); }
    void PushString(void* L, const char* s) { At<PushStringFn>(kPushString)(L, s); }
    void PushBoolean(void* L, bool b) { At<PushBooleanFn>(kPushBoolean)(L, b ? 1 : 0); }

    // Argument idx as a string, copied out of Lua, or false when it is not one.
    bool Arg(void* L, int idx, std::string& out)
    {
        if (GetTop(L) < idx || !At<IsStringFn>(kIsString)(L, idx))
            return false;
        const char* s = At<ToStringFn>(kToString)(L, idx);
        if (!s)
            return false;
        out = s;
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // The file

    const wchar_t kListFile[] = L"WTF\\comfylogin.txt";
    const wchar_t kOldFile[]  = L"Imports\\logins.txt";   // Nampower's, and paokkerkir's autologin's
    const DWORD   kMaxFile    = 4 * 1024 * 1024;

    std::wstring PathOf(const wchar_t* rel) { return std::wstring(g_dir) + rel; }

    bool Exists(const std::wstring& path)
    {
        return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
    }

    bool ReadText(const std::wstring& path, std::string& out)
    {
        HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        if (h == INVALID_HANDLE_VALUE)
            return false;
        LARGE_INTEGER size = {};
        bool ok = GetFileSizeEx(h, &size) && size.QuadPart <= kMaxFile;
        if (ok)
        {
            out.resize(static_cast<size_t>(size.QuadPart));
            DWORD got = 0;
            ok = out.empty() || (ReadFile(h, &out[0], static_cast<DWORD>(out.size()), &got, nullptr) &&
                                 got == out.size());
        }
        CloseHandle(h);
        return ok;
    }

    // To a .tmp file first, then over the old one, so a crash mid-write never leaves half a list.
    bool WriteText(const std::wstring& path, const std::string& text)
    {
        CreateDirectoryW(PathOf(L"WTF").c_str(), nullptr);
        const std::wstring tmp = path + L".tmp";
        HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h == INVALID_HANDLE_VALUE)
            return false;
        DWORD put = 0;
        bool ok = text.empty() ||
                  (WriteFile(h, text.data(), static_cast<DWORD>(text.size()), &put, nullptr) && put == text.size());
        ok = FlushFileBuffers(h) && ok;
        CloseHandle(h);
        if (ok)
            ok = MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
        if (!ok)
            DeleteFileW(tmp.c_str());
        return ok;
    }

    // ComfyLoginRead(): the list as text; nil when there is none; false when the file is there but
    // cannot be read, so that the Lua never writes over it. With no WTF\comfylogin.txt yet, it reads
    // Imports\logins.txt, and the first save moves the accounts to WTF.
    int __fastcall Lua_Read(void* L)
    {
        std::string text;
        const std::wstring list = PathOf(kListFile);
        if (Exists(list))
        {
            if (ReadText(list, text))
                PushString(L, text.c_str());
            else
                PushBoolean(L, false);
        }
        else if (ReadText(PathOf(kOldFile), text))
            PushString(L, text.c_str());
        else
            PushNil(L);
        return 1;
    }

    // ComfyLoginWrite(text): true, or nil when the file could not be written.
    int __fastcall Lua_Write(void* L)
    {
        std::string text;
        if (Arg(L, 1, text) && WriteText(PathOf(kListFile), text))
            PushBoolean(L, true);
        else
        {
            Log("could not write %ls", kListFile);
            PushNil(L);
        }
        return 1;
    }

    // ---------------------------------------------------------------------------------------------
    // Passwords

    // ":comfy:" and base64 DPAPI. On Windows the key comes from the user's Windows login: the text
    // decrypts only for the same Windows user on the same PC. Under Wine the key is the user name and a
    // fixed string, so there it only hides the password from a casual look.
    const char kPrefix[]  = ":comfy:";
    const size_t kPrefixLen = sizeof(kPrefix) - 1;
    // Not a secret: it keeps these blobs apart from other programs' DPAPI blobs.
    const char kEntropy[] = "comfylogin";

    DATA_BLOB EntropyBlob()
    {
        DATA_BLOB b;
        b.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(kEntropy));
        b.cbData = sizeof(kEntropy) - 1;
        return b;
    }

    bool Protect(const std::string& plain, std::string& out)
    {
        DATA_BLOB in;
        in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()));
        in.cbData = static_cast<DWORD>(plain.size());
        DATA_BLOB entropy = EntropyBlob();
        DATA_BLOB blob = {};
        if (!CryptProtectData(&in, L"comfylogin", &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &blob))
            return false;
        DWORD n = 0;
        const DWORD flags = CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF;
        bool ok = CryptBinaryToStringA(blob.pbData, blob.cbData, flags, nullptr, &n) && n > 0;
        if (ok)
        {
            std::string b64(n, '\0');
            ok = CryptBinaryToStringA(blob.pbData, blob.cbData, flags, &b64[0], &n) != 0;
            b64.resize(n);
            out = kPrefix + b64;
        }
        LocalFree(blob.pbData);
        return ok;
    }

    bool Unprotect(const std::string& value, std::string& plain)
    {
        if (value.compare(0, kPrefixLen, kPrefix) != 0)
            return false;
        const char* b64 = value.c_str() + kPrefixLen;
        DWORD n = 0;
        if (!CryptStringToBinaryA(b64, 0, CRYPT_STRING_BASE64, nullptr, &n, nullptr, nullptr) || n == 0)
            return false;
        std::string raw(n, '\0');
        if (!CryptStringToBinaryA(b64, 0, CRYPT_STRING_BASE64, reinterpret_cast<BYTE*>(&raw[0]), &n, nullptr, nullptr))
            return false;
        DATA_BLOB in;
        in.pbData = reinterpret_cast<BYTE*>(&raw[0]);
        in.cbData = n;
        DATA_BLOB entropy = EntropyBlob();
        DATA_BLOB out = {};
        if (!CryptUnprotectData(&in, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out))
            return false;
        plain.assign(reinterpret_cast<const char*>(out.pbData), out.cbData);
        SecureZeroMemory(out.pbData, out.cbData);
        LocalFree(out.pbData);
        return true;
    }

    // ComfyLoginEncrypt(password): ":comfy:..." or nil. A value that already has the prefix comes back
    // as it is.
    int __fastcall Lua_Encrypt(void* L)
    {
        std::string plain, out;
        if (Arg(L, 1, plain) && !plain.empty())
        {
            if (plain.compare(0, kPrefixLen, kPrefix) == 0)
                out = plain;
            else if (!Protect(plain, out))
                Log("CryptProtectData failed: %lu", GetLastError());
            SecureZeroMemory(&plain[0], plain.size());
        }
        if (out.empty())
            PushNil(L);
        else
            PushString(L, out.c_str());
        return 1;
    }

    // ComfyLoginCanDecrypt(value): true when this Windows user on this PC can decrypt it.
    int __fastcall Lua_CanDecrypt(void* L)
    {
        std::string value, plain;
        const bool ok = Arg(L, 1, value) && Unprotect(value, plain);
        if (!plain.empty())
            SecureZeroMemory(&plain[0], plain.size());
        PushBoolean(L, ok);
        return 1;
    }

    // The password the last ComfyLoginServerLogin sent. It stays until the next call, so the client is
    // never handed a pointer into freed memory.
    char g_password[256] = {};

    // ComfyLoginServerLogin(account, value): decrypts here and logs in. true, or nil when the value does
    // not decrypt.
    int __fastcall Lua_ServerLogin(void* L)
    {
        std::string user, value, plain;
        if (!Arg(L, 1, user) || !Arg(L, 2, value) || !Unprotect(value, plain) || plain.size() >= sizeof(g_password))
        {
            if (!plain.empty())
                SecureZeroMemory(&plain[0], plain.size());
            PushNil(L);
            return 1;
        }
        SecureZeroMemory(g_password, sizeof(g_password));
        memcpy(g_password, plain.data(), plain.size());
        SecureZeroMemory(&plain[0], plain.size());
        At<ServerLoginFn>(kServerLogin)(user.c_str(), g_password);
        PushBoolean(L, true);
        return 1;
    }

    // ---------------------------------------------------------------------------------------------
    // Registering, each time the login screen gets a Lua state

    // 0x46A7B0 builds the login screen's Lua state, then at 0x46A880 calls 0x46ABB0, which registers the
    // client's own glue functions. That call goes to GlueFunctions instead, which makes it and then
    // registers ours. The call site and not the head of 0x46ABB0: Nampower hooks the head, and Turtle
    // changed the body.
    const uintptr_t kGlueCall      = 0x46A880;
    const uintptr_t kGlueFunctions = 0x46ABB0;

    GlueFunctionsFn g_glueFunctions = nullptr;

    void __stdcall GlueFunctions()
    {
        g_glueFunctions();
        const auto reg = At<RegisterFn>(kRegister);
        reg("ComfyLoginRead", reinterpret_cast<void*>(&Lua_Read));
        reg("ComfyLoginWrite", reinterpret_cast<void*>(&Lua_Write));
        reg("ComfyLoginEncrypt", reinterpret_cast<void*>(&Lua_Encrypt));
        reg("ComfyLoginCanDecrypt", reinterpret_cast<void*>(&Lua_CanDecrypt));
        reg("ComfyLoginServerLogin", reinterpret_cast<void*>(&Lua_ServerLogin));
    }

    bool HookGlue()
    {
        unsigned char call[5] = {};
        if (!SafeCopy(kGlueCall + Slide(), call, 5) || call[0] != 0xE8)
        {
            Log("glue hook: no call at 0x46A880, left alone");
            return false;
        }
        int32_t rel = 0;
        memcpy(&rel, call + 1, 4);
        const uintptr_t site = kGlueCall + Slide();
        const uintptr_t target = site + 5 + rel;
        if (target != kGlueFunctions + Slide())
        {
            Log("glue hook: 0x46A880 calls 0x%08X, not 0x46ABB0, left alone", static_cast<unsigned>(target));
            return false;
        }
        g_glueFunctions = reinterpret_cast<GlueFunctionsFn>(target);
        const int32_t ours = static_cast<int32_t>(reinterpret_cast<uintptr_t>(&GlueFunctions) - (site + 5));
        if (!Patch(kGlueCall + 1, &ours, 4))
        {
            Log("glue hook: VirtualProtect failed");
            return false;
        }
        Log("glue hook: in place");
        return true;
    }

    void Attach(HMODULE self)
    {
        GetModuleFileNameW(nullptr, g_dir, MAX_PATH);
        if (wchar_t* slash = wcsrchr(g_dir, L'\\'))
            slash[1] = 0;
        GetModuleFileNameW(self, g_logPath, MAX_PATH);
        if (wchar_t* dot = wcsrchr(g_logPath, L'.'))
            wcscpy_s(dot, MAX_PATH - (dot - g_logPath), L".log");

        // One start per log: it is the first place to look when the panel does not show.
        FILE* f = nullptr;
        if (_wfopen_s(&f, g_logPath, L"w") == 0 && f)
            fclose(f);
        Log("comfylogin.dll loaded, client folder %ls", g_dir);

        SignatureOff();
        if (!ApiMatches())
        {
            Log("Lua functions: unknown client, not registered");
            return;
        }
        if (PointerCheckOff())
            HookGlue();
    }
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(module);
        Attach(module);
    }
    return TRUE;
}
