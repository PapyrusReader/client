# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright==1.56.0"]
# ///
"""Drive browser and toolbar history against a built Papyrus web app in a fresh Chrome profile."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
from threading import Thread

from playwright.sync_api import Page, expect, sync_playwright


class AppHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if "text/html" in self.headers.get("Accept", "") and not Path(self.translate_path(self.path)).is_file():
            self.path = "/index.html"
        super().do_GET()

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        super().end_headers()

    def log_message(self, *_args):
        pass


def check_history(page: Page, origin: str):
    def button(name):
        return page.get_by_role("button", name=name, exact=True)

    def field(name):
        return page.get_by_role("textbox", name=name, exact=True)

    def focus(label):
        element = field(label)
        element.focus()
        # Flutter attaches its editing session after the DOM input receives focus.
        expect(element).to_have_attribute("autocorrect", "on")

    original = "History field guide"
    draft = "Unpublished field guide"
    page.goto(origin)
    page.locator("flt-semantics-placeholder").evaluate("element => element.click()")
    button("Continue offline").click()
    button("Add book").first.click()
    page.get_by_text(re.compile("Add physical book")).click()
    for label, value in [("Title*", original), ("Author*", "Journey author")]:
        focus(label)
        page.keyboard.type(value)
        expect(field(label)).to_have_value(value)
    button("Add").click()
    page.get_by_role("group", name=re.compile(original)).click()
    button("Edit book").wait_for()
    expect(page).to_have_url(re.compile(r"/library/details/[^/]+$"))
    details_url = page.url
    editor_url = details_url.replace("/details/", "/edit/")
    button("Edit book").click()
    expect(page).to_have_url(editor_url)
    title = field("Title*")
    focus("Title*")
    expect(title).to_have_value(original)
    title.press("ControlOrMeta+a")
    page.keyboard.type(draft)
    expect(button("Save")).to_be_enabled()

    page.go_back()
    button("Keep editing").click()
    expect(page).to_have_url(editor_url)
    focus("Title*")
    expect(title).to_have_value(draft)
    button("Back").click()
    button("Discard").click()
    expect(page).to_have_url(details_url)
    expect(page.get_by_role("banner", name=original)).to_be_visible()
    page.go_forward()
    expect(page).to_have_url(editor_url)
    focus("Title*")
    expect(title).to_have_value(original)
    expect(button("Save")).to_be_disabled()

    for action in ["Discard", "Save"]:
        # Enter the editor as a fresh document without a retained GoRouter stack.
        page.goto("about:blank")
        page.goto(editor_url)
        page.locator("flt-semantics-placeholder").evaluate("element => element.click()")
        focus("Title*")
        expect(title).to_have_value(original)
        title.press("ControlOrMeta+a")
        page.keyboard.type(draft)
        expect(title).to_have_value(draft)
        expect(button("Save")).to_be_enabled()
        if action == "Discard":
            button("Back").click()
            button("Discard").click()
        else:
            button("Save").click()
        expect(page).to_have_url(details_url)
        expect(page.get_by_role("banner", name=original if action == "Discard" else draft)).to_be_visible()
        page.go_back()
        expect(page).to_have_url("about:blank")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path, help="Flutter web build directory")
    args = parser.parse_args()
    if not (args.site / "index.html").is_file():
        parser.error("Build the web app before starting the journey.")

    with ThreadingHTTPServer(("127.0.0.1", 0), partial(AppHandler, directory=args.site)) as server:
        worker = Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(channel="chrome")
                page = browser.new_page(viewport={"width": 430, "height": 900})
                try:
                    check_history(page, f"http://127.0.0.1:{server.server_port}")
                except Exception:
                    print(page.url, page.locator("body").aria_snapshot(), flush=True)
                    raise
                finally:
                    browser.close()
        finally:
            server.shutdown()
            worker.join()
    print("Browser Back, toolbar Back and browser Forward preserved the expected title and URL.")


if __name__ == "__main__":
    main()
