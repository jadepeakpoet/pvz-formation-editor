#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// A pending close keeps the view/engine alive while Dart flushes the draft.
struct CloseState {
  gboolean pending;
  gboolean destroyed;
};

static void close_window_destroyed(GtkWidget* window, gpointer user_data) {
  static_cast<CloseState*>(user_data)->destroyed = TRUE;
}

static gboolean close_window_idle(gpointer user_data) {
  GtkWidget* window = GTK_WIDGET(user_data);
  auto* state = static_cast<CloseState*>(
      g_object_get_data(G_OBJECT(window), "pvz-close-state"));
  if (state != nullptr && !state->destroyed) gtk_widget_destroy(window);
  g_object_unref(window);
  return G_SOURCE_REMOVE;
}

static void prepare_exit_finished(GObject* source, GAsyncResult* result,
                                  gpointer user_data) {
  GtkWidget* window = GTK_WIDGET(user_data);
  auto* state = static_cast<CloseState*>(
      g_object_get_data(G_OBJECT(window), "pvz-close-state"));
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  FlValue* value = response != nullptr
      ? fl_method_response_get_result(response, &error) : nullptr;
  if (state != nullptr && !state->destroyed) {
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(value)) {
      // gtk_widget_destroy bypasses delete-event; no recursive close request.
      g_idle_add(close_window_idle, g_object_ref(window));
    } else {
      state->pending = FALSE;
      if (error != nullptr) g_warning("Draft flush prevented close: %s", error->message);
    }
  }
  g_object_unref(window);
}

static gboolean close_window_requested(GtkWidget* window, GdkEvent* event,
                                        gpointer user_data) {
  auto* state = static_cast<CloseState*>(
      g_object_get_data(G_OBJECT(window), "pvz-close-state"));
  if (state->pending) return TRUE;
  state->pending = TRUE;
  fl_method_channel_invoke_method(FL_METHOD_CHANNEL(user_data), "prepareExit",
      nullptr, nullptr, prepare_exit_finished, g_object_ref(window));
  return TRUE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "植物大战僵尸布阵器");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "植物大战僵尸布阵器");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) lifecycle_codec = fl_standard_method_codec_new();
  FlMethodChannel* lifecycle_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "pvz_formation_editor/lifecycle",
      FL_METHOD_CODEC(lifecycle_codec));
  auto* close_state = g_new0(CloseState, 1);
  g_object_set_data_full(G_OBJECT(window), "pvz-close-state", close_state, g_free);
  g_object_set_data_full(G_OBJECT(window), "pvz-lifecycle-channel",
                        lifecycle_channel, g_object_unref);
  g_signal_connect(window, "destroy", G_CALLBACK(close_window_destroyed), close_state);
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window_requested),
                   lifecycle_channel);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
