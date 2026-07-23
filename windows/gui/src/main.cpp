#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <string>
#include <vector>
#include <sstream>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "shell32.lib")

// ── Control IDs ────────────────────────────────────────────────────────────────
#define IDI_APP_ICON                100

#define ID_TAB_CONTROL              2000
#define ID_COMBO_TUNNELS            2001
#define ID_BTN_REFRESH              2002
#define ID_STATUS_TEXT              2003

// Tab 1 Buttons (Tunnels)
#define ID_BTN_CREATE_TUNNEL        2010
#define ID_BTN_EDIT_CONFIG          2011
#define ID_BTN_ROUTE_DNS            2012
#define ID_BTN_RUN_MANUAL           2013
#define ID_BTN_DELETE_TUNNEL        2014

// Tab 2 Buttons (Service & Boot Autostart)
#define ID_BTN_ENABLE_BOOT          2020
#define ID_BTN_DISABLE_BOOT         2021
#define ID_BTN_START_SVC            2022
#define ID_BTN_STOP_SVC             2023
#define ID_BTN_RESTART_SVC          2024
#define ID_BTN_VIEW_LOGS            2025
#define ID_BTN_REMOVE_SVC           2026

// Tab 3 Buttons (Setup & Uninstall)
#define ID_BTN_INSTALL_CLOUDFLARED  2030
#define ID_BTN_LOGIN_CLOUDFLARE     2031
#define ID_BTN_FULL_UNINSTALL       2032

// Log Box
#define ID_LOG_EDIT                 2040
#define ID_INPUT_EDIT               2050

// ── Globals ───────────────────────────────────────────────────────────────────
HINSTANCE g_hInstance = NULL;
HWND g_hMainWnd = NULL;
HWND g_hTab = NULL;
HWND g_hComboTunnels = NULL;
HWND g_hStatusText = NULL;
HWND g_hLogEdit = NULL;
HFONT g_hFontUi = NULL;
HFONT g_hFontBold = NULL;

std::vector<HWND> g_tab1Controls;
std::vector<HWND> g_tab2Controls;
std::vector<HWND> g_tab3Controls;

HBRUSH g_hBgBrush = NULL;
COLORREF g_colBg = RGB(30, 30, 36);
COLORREF g_colText = RGB(240, 240, 245);

std::wstring g_inputResult = L"";

// ── Helper: Execute PowerShell Action & Stream Output ─────────────────────────
std::wstring RunPSAction(const std::wstring& actionParams) {
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(NULL, exePath, MAX_PATH);
    std::wstring currentDir(exePath);
    size_t lastSlash = currentDir.find_last_of(L"\\/");
    if (lastSlash != std::wstring::npos) {
        currentDir = currentDir.substr(0, lastSlash);
    }

    std::wstring scriptPath = currentDir + L"\\cloudflare-tunnel-manager.ps1";
    if (GetFileAttributesW(scriptPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        scriptPath = currentDir + L"\\..\\cloudflare-tunnel-manager.ps1";
    }
    if (GetFileAttributesW(scriptPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        scriptPath = currentDir + L"\\..\\windows\\cloudflare-tunnel-manager.ps1";
    }

    std::wstring fullCmd = L"powershell.exe -ExecutionPolicy Bypass -NoProfile -File \"" + scriptPath + L"\" " + actionParams;

    SECURITY_ATTRIBUTES saAttr = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };
    HANDLE hReadPipe = NULL, hWritePipe = NULL;
    if (!CreatePipe(&hReadPipe, &hWritePipe, &saAttr, 0)) return L"Error creating pipe";
    SetHandleInformation(hReadPipe, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si = { 0 };
    si.cb = sizeof(STARTUPINFOW);
    si.hStdOutput = hWritePipe;
    si.hStdError = hWritePipe;
    si.dwFlags |= STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION pi = { 0 };
    std::vector<wchar_t> cmdBuffer(fullCmd.begin(), fullCmd.end());
    cmdBuffer.push_back(L'\0');

    if (!CreateProcessW(NULL, cmdBuffer.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        CloseHandle(hWritePipe);
        CloseHandle(hReadPipe);
        return L"Failed to execute process";
    }

    CloseHandle(hWritePipe);

    char buffer[1024];
    DWORD bytesRead = 0;
    std::string resultStr = "";

    while (ReadFile(hReadPipe, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
        buffer[bytesRead] = '\0';
        resultStr += buffer;
    }

    CloseHandle(hReadPipe);
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    int wlen = MultiByteToWideChar(CP_UTF8, 0, resultStr.c_str(), -1, NULL, 0);
    if (wlen > 0) {
        std::vector<wchar_t> wbuf(wlen);
        MultiByteToWideChar(CP_UTF8, 0, resultStr.c_str(), -1, &wbuf[0], wlen);
        return std::wstring(&wbuf[0]);
    }
    return L"";
}

void LogMessage(const std::wstring& msg) {
    if (!g_hLogEdit) return;
    int len = GetWindowTextLengthW(g_hLogEdit);
    SendMessageW(g_hLogEdit, EM_SETSEL, (WPARAM)len, (LPARAM)len);
    std::wstring formatted = msg + L"\r\n";
    SendMessageW(g_hLogEdit, EM_REPLACESEL, FALSE, (LPARAM)formatted.c_str());
}

// Set Segoe UI Font on Window
void SetUIFont(HWND hwnd, HFONT font) {
    SendMessageW(hwnd, WM_SETFONT, (WPARAM)font, TRUE);
}

// ── Refresh Tunnel List (Does NOT auto-select a tunnel) ─────────────────────
void RefreshTunnelList() {
    if (!g_hComboTunnels) return;
    SendMessageW(g_hComboTunnels, CB_RESETCONTENT, 0, 0);

    // Add default prompt option at index 0 so user MUST manually select a tunnel
    SendMessageW(g_hComboTunnels, CB_ADDSTRING, 0, (LPARAM)L"-- Select a Tunnel --");

    std::wstring listOutput = L"";

    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(NULL, exePath, MAX_PATH);
    std::wstring currentDir(exePath);
    size_t lastSlash = currentDir.find_last_of(L"\\/");
    if (lastSlash != std::wstring::npos) currentDir = currentDir.substr(0, lastSlash);

    std::wstring fullCmd = L"cmd.exe /c \"cloudflared tunnel list 2>&1\"";
    SECURITY_ATTRIBUTES saAttr = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };
    HANDLE hReadPipe = NULL, hWritePipe = NULL;
    CreatePipe(&hReadPipe, &hWritePipe, &saAttr, 0);
    SetHandleInformation(hReadPipe, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si = { 0 };
    si.cb = sizeof(STARTUPINFOW);
    si.hStdOutput = hWritePipe;
    si.hStdError = hWritePipe;
    si.dwFlags |= STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION pi = { 0 };
    std::vector<wchar_t> cmdBuffer(fullCmd.begin(), fullCmd.end());
    cmdBuffer.push_back(L'\0');

    if (CreateProcessW(NULL, cmdBuffer.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        CloseHandle(hWritePipe);
        char buffer[1024];
        DWORD bytesRead = 0;
        std::string res = "";
        while (ReadFile(hReadPipe, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
            buffer[bytesRead] = '\0';
            res += buffer;
        }
        CloseHandle(hReadPipe);
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);

        int wlen = MultiByteToWideChar(CP_UTF8, 0, res.c_str(), -1, NULL, 0);
        if (wlen > 0) {
            std::vector<wchar_t> wbuf(wlen);
            MultiByteToWideChar(CP_UTF8, 0, res.c_str(), -1, &wbuf[0], wlen);
            listOutput = std::wstring(&wbuf[0]);
        }
    } else {
        CloseHandle(hWritePipe);
        CloseHandle(hReadPipe);
    }

    std::wstringstream ss(listOutput);
    std::wstring line;

    while (std::getline(ss, line)) {
        if (line.empty()) continue;
        size_t spacePos = line.find_first_of(L" \t");
        if (spacePos != std::wstring::npos && spacePos == 36) {
            std::wstring rest = line.substr(spacePos);
            size_t nameStart = rest.find_first_not_of(L" \t");
            if (nameStart != std::wstring::npos) {
                std::wstring nameRest = rest.substr(nameStart);
                size_t nameEnd = nameRest.find_first_of(L" \t\r\n");
                std::wstring tName = (nameEnd == std::wstring::npos) ? nameRest : nameRest.substr(0, nameEnd);
                if (!tName.empty() && tName != L"NAME") {
                    SendMessageW(g_hComboTunnels, CB_ADDSTRING, 0, (LPARAM)tName.c_str());
                }
            }
        }
    }

    // Always select Index 0 ("-- Select a Tunnel --") by default
    SendMessageW(g_hComboTunnels, CB_SETCURSEL, 0, 0);
}

// ── Check Service Status ───────────────────────────────────────────────────────
void UpdateServiceStatus() {
    SC_HANDLE hSCManager = OpenSCManager(NULL, NULL, SC_MANAGER_CONNECT);
    if (!hSCManager) {
        SetWindowTextW(g_hStatusText, L"Service Status: Unknown (No SCM Access)");
        return;
    }

    SC_HANDLE hService = OpenServiceW(hSCManager, L"Cloudflared", SERVICE_QUERY_STATUS);
    if (!hService) {
        SetWindowTextW(g_hStatusText, L"Service Status: 🔴 Not Installed");
        CloseServiceHandle(hSCManager);
        return;
    }

    SERVICE_STATUS_PROCESS ssp;
    DWORD bytesNeeded;
    if (QueryServiceStatusEx(hService, SC_STATUS_PROCESS_INFO, (LPBYTE)&ssp, sizeof(SERVICE_STATUS_PROCESS), &bytesNeeded)) {
        if (ssp.dwCurrentState == SERVICE_RUNNING) {
            SetWindowTextW(g_hStatusText, L"Service Status: 🟢 Running (Boot Autostart Active)");
        } else if (ssp.dwCurrentState == SERVICE_STOPPED) {
            SetWindowTextW(g_hStatusText, L"Service Status: 🔴 Stopped");
        } else {
            SetWindowTextW(g_hStatusText, L"Service Status: 🟡 Pending State");
        }
    }
    CloseServiceHandle(hService);
    CloseServiceHandle(hSCManager);
}

// Returns selected tunnel name or empty string if "-- Select a Tunnel --" is selected
std::wstring GetSelectedTunnel() {
    int sel = (int)SendMessageW(g_hComboTunnels, CB_GETCURSEL, 0, 0);
    if (sel == CB_ERR || sel == 0) return L"";
    wchar_t tName[256];
    SendMessageW(g_hComboTunnels, CB_GETLBTEXT, sel, (LPARAM)tName);
    std::wstring res(tName);
    if (res == L"-- Select a Tunnel --") return L"";
    return res;
}

// ── Input Prompt Dialog ────────────────────────────────────────────────────────
INT_PTR CALLBACK InputDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_INITDIALOG:
        SetWindowTextW(hDlg, (LPCWSTR)lParam);
        return TRUE;
    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK) {
            wchar_t buf[512];
            GetDlgItemTextW(hDlg, ID_INPUT_EDIT, buf, 512);
            g_inputResult = std::wstring(buf);
            EndDialog(hDlg, IDOK);
            return TRUE;
        } else if (LOWORD(wParam) == IDCANCEL) {
            g_inputResult = L"";
            EndDialog(hDlg, IDCANCEL);
            return TRUE;
        }
        break;
    }
    return FALSE;
}

std::wstring PromptInput(const std::wstring& title, const std::wstring& promptText) {
    g_inputResult = L"";

    struct DialogTemplate {
        DLGTEMPLATE dlg;
        WORD menu;
        WORD windowClass;
        WCHAR title[128];
    } dt = { 0 };

    dt.dlg.style = DS_MODALFRAME | WS_POPUP | WS_CAPTION | WS_SYSMENU;
    dt.dlg.cx = 240;
    dt.dlg.cy = 80;

    wcsncpy_s(dt.title, title.c_str(), 127);

    HWND hDlg = CreateDialogIndirectParamW(g_hInstance, &dt.dlg, g_hMainWnd, InputDlgProc, (LPARAM)title.c_str());
    if (hDlg) {
        HWND hL = CreateWindowW(L"STATIC", promptText.c_str(), WS_CHILD | WS_VISIBLE, 15, 10, 300, 20, hDlg, NULL, g_hInstance, NULL);
        HWND hE = CreateWindowW(WC_EDITW, L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 15, 32, 320, 24, hDlg, (HMENU)ID_INPUT_EDIT, g_hInstance, NULL);
        HWND hB1 = CreateWindowW(WC_BUTTONW, L"OK", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 175, 75, 75, 26, hDlg, (HMENU)IDOK, g_hInstance, NULL);
        HWND hB2 = CreateWindowW(WC_BUTTONW, L"Cancel", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 260, 75, 75, 26, hDlg, (HMENU)IDCANCEL, g_hInstance, NULL);

        SetUIFont(hL, g_hFontUi); SetUIFont(hE, g_hFontUi);
        SetUIFont(hB1, g_hFontUi); SetUIFont(hB2, g_hFontUi);

        SetWindowPos(hDlg, NULL, 0, 0, 370, 150, SWP_NOMOVE | SWP_NOZORDER);
        ShowWindow(hDlg, SW_SHOW);

        MSG msg;
        while (IsWindow(hDlg) && GetMessageW(&msg, NULL, 0, 0)) {
            if (!IsDialogMessageW(hDlg, &msg)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }

    return g_inputResult;
}

// ── Show/Hide Tab Controls ─────────────────────────────────────────────────────
void ShowTabControls(int tabIndex) {
    for (HWND h : g_tab1Controls) ShowWindow(h, (tabIndex == 0) ? SW_SHOW : SW_HIDE);
    for (HWND h : g_tab2Controls) ShowWindow(h, (tabIndex == 1) ? SW_SHOW : SW_HIDE);
    for (HWND h : g_tab3Controls) ShowWindow(h, (tabIndex == 2) ? SW_SHOW : SW_HIDE);
}

// ── Window Procedure ───────────────────────────────────────────────────────────
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        // Enable Immersive Dark Mode
        BOOL useDark = TRUE;
        DwmSetWindowAttribute(hWnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &useDark, sizeof(useDark));

        // Load Custom Application Icon into Window Titlebar and Taskbar
        HICON hIconBig = LoadIconW(g_hInstance, MAKEINTRESOURCEW(IDI_APP_ICON));
        HICON hIconSm = (HICON)LoadImageW(g_hInstance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, 16, 16, LR_DEFAULTCOLOR);
        if (hIconBig) SendMessageW(hWnd, WM_SETICON, ICON_BIG, (LPARAM)hIconBig);
        if (hIconSm) SendMessageW(hWnd, WM_SETICON, ICON_SMALL, (LPARAM)hIconSm);

        // Create Modern Segoe UI Fonts
        g_hFontUi = CreateFontW(15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, ANSI_CHARSET,
            OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

        g_hFontBold = CreateFontW(15, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
            OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

        // Header Title Label & Status Pill
        HWND hTitle = CreateWindowW(L"STATIC", L"🚀 Cloudflare Tunnel Manager", WS_CHILD | WS_VISIBLE,
            20, 12, 280, 24, hWnd, NULL, g_hInstance, NULL);
        SetUIFont(hTitle, g_hFontBold);

        g_hStatusText = CreateWindowW(L"STATIC", L"Service Status: Checking...", WS_CHILD | WS_VISIBLE,
            300, 12, 330, 24, hWnd, (HMENU)ID_STATUS_TEXT, g_hInstance, NULL);
        SetUIFont(g_hStatusText, g_hFontBold);

        // Tunnel Selector Section
        HWND hSelectLbl = CreateWindowW(L"STATIC", L"Target Tunnel:", WS_CHILD | WS_VISIBLE, 20, 44, 95, 24, hWnd, NULL, g_hInstance, NULL);
        SetUIFont(hSelectLbl, g_hFontUi);

        g_hComboTunnels = CreateWindowW(WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
            120, 42, 250, 200, hWnd, (HMENU)ID_COMBO_TUNNELS, g_hInstance, NULL);
        SetUIFont(g_hComboTunnels, g_hFontUi);

        HWND hBtnRef = CreateWindowW(WC_BUTTONW, L"🔄 Refresh", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            380, 41, 95, 27, hWnd, (HMENU)ID_BTN_REFRESH, g_hInstance, NULL);
        SetUIFont(hBtnRef, g_hFontUi);

        // Tab Control
        g_hTab = CreateWindowW(WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
            20, 75, 600, 110, hWnd, (HMENU)ID_TAB_CONTROL, g_hInstance, NULL);
        SetUIFont(g_hTab, g_hFontUi);

        TCITEMW tie = { 0 };
        tie.mask = TCIF_TEXT;
        tie.pszText = (LPWSTR)L"🚀 Tunnels (3,4,5,6,11)";
        TabCtrl_InsertItem(g_hTab, 0, &tie);
        tie.pszText = (LPWSTR)L"⚙️ Service & Boot (7,8,9)";
        TabCtrl_InsertItem(g_hTab, 1, &tie);
        tie.pszText = (LPWSTR)L"📦 Setup & Cleanup (1,2,10)";
        TabCtrl_InsertItem(g_hTab, 2, &tie);

        // ── Tab 1 Controls (Tunnels: 3, 4, 5, 6, 11) ──────────────────────────
        HWND h;
        h = CreateWindowW(WC_BUTTONW, L"➕ 3. Create Tunnel", WS_CHILD | BS_PUSHBUTTON, 30, 115, 130, 30, hWnd, (HMENU)ID_BTN_CREATE_TUNNEL, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab1Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"📝 4. Edit Config", WS_CHILD | BS_PUSHBUTTON, 170, 115, 120, 30, hWnd, (HMENU)ID_BTN_EDIT_CONFIG, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab1Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🌐 5. Route Subdomain", WS_CHILD | BS_PUSHBUTTON, 300, 115, 140, 30, hWnd, (HMENU)ID_BTN_ROUTE_DNS, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab1Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"▶️ 6. Run Manual", WS_CHILD | BS_PUSHBUTTON, 450, 115, 120, 30, hWnd, (HMENU)ID_BTN_RUN_MANUAL, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab1Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🗑️ 11. Delete Tunnel", WS_CHILD | BS_PUSHBUTTON, 30, 150, 130, 26, hWnd, (HMENU)ID_BTN_DELETE_TUNNEL, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab1Controls.push_back(h);

        // ── Tab 2 Controls (Service & Autostart: 7, 8, 9) ─────────────────────
        h = CreateWindowW(WC_BUTTONW, L"⚡ 7. Enable Autostart", WS_CHILD | BS_PUSHBUTTON, 30, 115, 140, 30, hWnd, (HMENU)ID_BTN_ENABLE_BOOT, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🛑 7. Disable Autostart", WS_CHILD | BS_PUSHBUTTON, 180, 115, 140, 30, hWnd, (HMENU)ID_BTN_DISABLE_BOOT, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"▶️ 8. Start Svc", WS_CHILD | BS_PUSHBUTTON, 330, 115, 110, 30, hWnd, (HMENU)ID_BTN_START_SVC, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"⏹️ 8. Stop Svc", WS_CHILD | BS_PUSHBUTTON, 450, 115, 110, 30, hWnd, (HMENU)ID_BTN_STOP_SVC, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🔄 8. Restart Svc", WS_CHILD | BS_PUSHBUTTON, 30, 150, 140, 26, hWnd, (HMENU)ID_BTN_RESTART_SVC, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"📜 8. View Logs", WS_CHILD | BS_PUSHBUTTON, 180, 150, 140, 26, hWnd, (HMENU)ID_BTN_VIEW_LOGS, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🧹 9. Delete Service", WS_CHILD | BS_PUSHBUTTON, 330, 150, 140, 26, hWnd, (HMENU)ID_BTN_REMOVE_SVC, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab2Controls.push_back(h);

        // ── Tab 3 Controls (Setup & Full Cleanup: 1, 2, 10) ────────────────────
        h = CreateWindowW(WC_BUTTONW, L"📥 1. Install cloudflared", WS_CHILD | BS_PUSHBUTTON, 30, 115, 170, 32, hWnd, (HMENU)ID_BTN_INSTALL_CLOUDFLARED, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab3Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"🔐 2. Login Authenticate", WS_CHILD | BS_PUSHBUTTON, 210, 115, 170, 32, hWnd, (HMENU)ID_BTN_LOGIN_CLOUDFLARE, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab3Controls.push_back(h);
        h = CreateWindowW(WC_BUTTONW, L"❌ 10. Full Uninstall All", WS_CHILD | BS_PUSHBUTTON, 390, 115, 170, 32, hWnd, (HMENU)ID_BTN_FULL_UNINSTALL, g_hInstance, NULL); SetUIFont(h, g_hFontUi); g_tab3Controls.push_back(h);

        // Output Log Textbox
        g_hLogEdit = CreateWindowW(WC_EDITW, L"", WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY,
            20, 195, 600, 255, hWnd, (HMENU)ID_LOG_EDIT, g_hInstance, NULL);
        SetUIFont(g_hLogEdit, g_hFontUi);

        ShowTabControls(0);
        RefreshTunnelList();
        UpdateServiceStatus();
        LogMessage(L"🚀 Cloudflare Tunnel Manager GUI started.");
        LogMessage(L"ℹ️ Please select a tunnel from the 'Target Tunnel' dropdown menu to begin.");
        return 0;
    }

    case WM_NOTIFY: {
        LPNMHDR pnmh = (LPNMHDR)lParam;
        if (pnmh->idFrom == ID_TAB_CONTROL && pnmh->code == TCN_SELCHANGE) {
            int sel = TabCtrl_GetCurSel(g_hTab);
            ShowTabControls(sel);
        }
        return 0;
    }

    case WM_COMMAND: {
        int wmId = LOWORD(wParam);
        std::wstring tName = GetSelectedTunnel();

        switch (wmId) {
        case ID_BTN_REFRESH:
            RefreshTunnelList();
            UpdateServiceStatus();
            LogMessage(L"🔄 Refreshed tunnel list & service status.");
            break;

        // ── 1. Install cloudflared ──
        case ID_BTN_INSTALL_CLOUDFLARED:
            LogMessage(L"📥 Function 1: Installing cloudflared CLI...");
            LogMessage(RunPSAction(L"-Action InstallCloudflared"));
            RefreshTunnelList();
            UpdateServiceStatus();
            break;

        // ── 2. Authenticate ──
        case ID_BTN_LOGIN_CLOUDFLARE:
            LogMessage(L"🔐 Function 2: Launching Cloudflare login...");
            LogMessage(RunPSAction(L"-Action LoginCloudflare"));
            break;

        // ── 3. Create Tunnel ──
        case ID_BTN_CREATE_TUNNEL: {
            std::wstring newName = PromptInput(L"Create New Tunnel", L"Enter tunnel name:");
            if (!newName.empty()) {
                LogMessage(L"⛏️ Function 3: Creating tunnel '" + newName + L"'...");
                LogMessage(RunPSAction(L"-Action NewTunnel -TunnelName \"" + newName + L"\""));
                RefreshTunnelList();
            }
            break;
        }

        // ── 4. Edit Config ──
        case ID_BTN_EDIT_CONFIG:
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            LogMessage(L"📝 Function 4: Opening config for '" + tName + L"'...");
            RunPSAction(L"-Action EditTunnelConfig -TunnelName \"" + tName + L"\"");
            break;

        // ── 5. Route Subdomain ──
        case ID_BTN_ROUTE_DNS: {
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            std::wstring domain = PromptInput(L"Route Subdomain", L"Enter subdomain (e.g. dev.example.com):");
            if (!domain.empty()) {
                LogMessage(L"🌐 Function 5: Routing " + domain + L" to '" + tName + L"'...");
                LogMessage(RunPSAction(L"-Action AddDnsRoute -TunnelName \"" + tName + L"\" -Domain \"" + domain + L"\""));
            }
            break;
        }

        // ── 6. Run Manual ──
        case ID_BTN_RUN_MANUAL:
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            LogMessage(L"🚀 Function 6: Starting manual tunnel for '" + tName + L"'...");
            LogMessage(RunPSAction(L"-Action StartTunnelManual -TunnelName \"" + tName + L"\""));
            break;

        // ── 7. Enable Autostart ──
        case ID_BTN_ENABLE_BOOT:
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            LogMessage(L"⚡ Function 7: Enabling autostart service for '" + tName + L"'...");
            LogMessage(RunPSAction(L"-Action EnableAutostart -TunnelName \"" + tName + L"\""));
            UpdateServiceStatus();
            break;

        // ── 7. Disable Autostart ──
        case ID_BTN_DISABLE_BOOT:
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            LogMessage(L"🛑 Function 7: Disabling autostart service for '" + tName + L"'...");
            LogMessage(RunPSAction(L"-Action DisableAutostart -TunnelName \"" + tName + L"\""));
            UpdateServiceStatus();
            break;

        // ── 8. Start Service ──
        case ID_BTN_START_SVC:
            LogMessage(L"🚀 Function 8: Starting Cloudflared service...");
            LogMessage(RunPSAction(L"-Action ManageService -SubAction \"a\""));
            UpdateServiceStatus();
            break;

        // ── 8. Stop Service ──
        case ID_BTN_STOP_SVC:
            LogMessage(L"🛑 Function 8: Stopping Cloudflared service...");
            LogMessage(RunPSAction(L"-Action ManageService -SubAction \"b\""));
            UpdateServiceStatus();
            break;

        // ── 8. Restart Service ──
        case ID_BTN_RESTART_SVC:
            LogMessage(L"🔄 Function 8: Restarting Cloudflared service...");
            LogMessage(RunPSAction(L"-Action ManageService -SubAction \"a\""));
            UpdateServiceStatus();
            break;

        // ── 8. View Service Logs ──
        case ID_BTN_VIEW_LOGS:
            LogMessage(L"📜 Function 8: Fetching Cloudflared service logs...");
            LogMessage(RunPSAction(L"-Action ManageService -SubAction \"d\""));
            break;

        // ── 9. Delete Service ──
        case ID_BTN_REMOVE_SVC:
            LogMessage(L"🧹 Function 9: Removing Cloudflared Windows service...");
            LogMessage(RunPSAction(L"-Action RemoveService"));
            UpdateServiceStatus();
            break;

        // ── 10. Full Uninstall ──
        case ID_BTN_FULL_UNINSTALL:
            if (MessageBoxW(hWnd, L"Are you sure you want to run FULL UNINSTALL? This removes cloudflared, all tunnels, configs, and services.", L"Confirm Full Uninstall", MB_YESNO | MB_ICONWARNING) == IDYES) {
                LogMessage(L"❌ Function 10: Running full system uninstall...");
                LogMessage(RunPSAction(L"-Action FullUninstall"));
                RefreshTunnelList();
                UpdateServiceStatus();
            }
            break;

        // ── 11. Delete Tunnel ──
        case ID_BTN_DELETE_TUNNEL:
            if (tName.empty()) { MessageBoxW(hWnd, L"⚠️ Please select a target tunnel from the dropdown menu first.", L"Tunnel Required", MB_ICONWARNING); break; }
            if (MessageBoxW(hWnd, (L"Are you sure you want to delete tunnel '" + tName + L"'?").c_str(), L"Confirm Tunnel Deletion", MB_YESNO | MB_ICONWARNING) == IDYES) {
                LogMessage(L"🗑️ Function 11: Deleting tunnel '" + tName + L"'...");
                LogMessage(RunPSAction(L"-Action DeleteTunnel -TunnelName \"" + tName + L"\""));
                RefreshTunnelList();
            }
            break;
        }
        return 0;
    }

    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLOREDIT: {
        HDC hdcStatic = (HDC)wParam;
        SetTextColor(hdcStatic, g_colText);
        SetBkColor(hdcStatic, g_colBg);
        return (INT_PTR)g_hBgBrush;
    }

    case WM_DESTROY:
        if (g_hFontUi) DeleteObject(g_hFontUi);
        if (g_hFontBold) DeleteObject(g_hFontBold);
        if (g_hBgBrush) DeleteObject(g_hBgBrush);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hWnd, msg, wParam, lParam);
}

// ── WinMain Entry Point ────────────────────────────────────────────────────────
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR pCmdLine, int nCmdShow) {
    g_hInstance = hInstance;
    InitCommonControls();

    g_hBgBrush = CreateSolidBrush(g_colBg);

    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hbrBackground = g_hBgBrush;
    wc.lpszClassName = L"CloudflareTunnelManagerWndClass";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hIcon = LoadIconW(hInstance, MAKEINTRESOURCEW(IDI_APP_ICON));

    RegisterClassW(&wc);

    g_hMainWnd = CreateWindowExW(
        0,
        L"CloudflareTunnelManagerWndClass",
        L"Cloudflare Tunnel Manager (Windows GUI)",
        WS_OVERLAPPEDWINDOW ^ WS_THICKFRAME ^ WS_MAXIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 655, 500,
        NULL, NULL, hInstance, NULL
    );

    ShowWindow(g_hMainWnd, nCmdShow);
    UpdateWindow(g_hMainWnd);

    MSG msg = { 0 };
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    return (int)msg.wParam;
}
