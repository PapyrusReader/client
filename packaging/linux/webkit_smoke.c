#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

static int result = 1;

static gboolean timed_out(gpointer data) {
  g_printerr("WebKit render check timed out\n");
  gtk_main_quit();
  return G_SOURCE_REMOVE;
}

static void title_changed(WebKitWebView* view, GParamSpec* spec, gpointer data) {
  if (g_strcmp0(webkit_web_view_get_title(view), "PAPYRUS_RENDER_OK") == 0) {
    result = 0;
    gtk_main_quit();
  }
}

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  WebKitWebView* view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_signal_connect(view, "notify::title", G_CALLBACK(title_changed), NULL);
  gtk_widget_show_all(window);
  g_timeout_add_seconds(30, timed_out, NULL);
  webkit_web_view_load_html(view,
    "<!doctype html><body><p id='text'>Papyrus</p><canvas id='page'></canvas>"
    "<script>requestAnimationFrame(() => {"
    "const c = document.getElementById('page').getContext('2d');"
    "c.fillRect(0,0,20,20);"
    "if (document.getElementById('text').getBoundingClientRect().height > 0) "
    "document.title = 'PAPYRUS_RENDER_OK';"
    "});</script></body>", "http://localhost/");
  gtk_main();
  return result;
}
