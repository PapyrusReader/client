#include <windows.h>
#include <wrl.h>
#include <WebView2.h>
#include <string>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

// Runs only in packaging validation; never installed with Papyrus.
int wmain(int argc, wchar_t** argv) {
  if (argc != 3 || FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {
    return 1;
  }

  HMODULE loader = LoadLibraryW(argv[1]);
  if (!loader) {
    return 2;
  }

  auto create = reinterpret_cast<decltype(&CreateCoreWebView2EnvironmentWithOptions)>(
      GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions"));
  if (!create) {
    return 3;
  }

  HWND window = CreateWindowExW(0, L"STATIC", L"Papyrus WebView2 packaging check",
      WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, 640, 480, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (!window) {
    return 4;
  }

  bool finished = false;
  int result = 1;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> view;
  HRESULT started = create(nullptr, argv[2], nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [&](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
            if (FAILED(status) || !environment) {
              finished = true;
              return S_OK;
            }

            HRESULT creating = environment->CreateCoreWebView2Controller(window,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [&](HRESULT status, ICoreWebView2Controller* created) -> HRESULT {
                      if (FAILED(status) || !created) {
                        finished = true;
                        return S_OK;
                      }

                      controller = created;
                      controller->get_CoreWebView2(&view);
                      RECT bounds;
                      GetClientRect(window, &bounds);
                      controller->put_Bounds(bounds);
                      EventRegistrationToken token;
                      view->add_WebMessageReceived(
                          Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                              [&](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* event) -> HRESULT {
                                LPWSTR message = nullptr;
                                if (SUCCEEDED(event->TryGetWebMessageAsString(&message))) {
                                  result = std::wstring(message) == L"PAPYRUS_RENDER_OK" ? 0 : 1;
                                  CoTaskMemFree(message);
                                  finished = true;
                                }
                                return S_OK;
                              }).Get(), &token);
                      view->NavigateToString(L"<!doctype html><p id='text'>Papyrus</p><canvas id='page'></canvas>"
                          L"<script>requestAnimationFrame(() => {const c=document.getElementById('page').getContext('2d');"
                          L"c.fillRect(0,0,20,20);if(document.getElementById('text').getBoundingClientRect().height>0)"
                          L"chrome.webview.postMessage('PAPYRUS_RENDER_OK');});</script>");
                      return S_OK;
                    }).Get());
            if (FAILED(creating)) {
              finished = true;
            }
            return S_OK;
          }).Get());

  ULONGLONG deadline = GetTickCount64() + 45000;
  while (SUCCEEDED(started) && !finished && GetTickCount64() < deadline) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT);
  }

  if (controller) {
    controller->Close();
  }
  view.Reset();
  controller.Reset();
  DestroyWindow(window);
  CoUninitialize();
  return result;
}
