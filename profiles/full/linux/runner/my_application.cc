#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <cstring>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* link_opens;
  gboolean link_opens_listening;
  GPtrArray* pending_link_opens;
};

// A `discourse://open?url=<page>` request reaches the running instance as this
// action's string parameter, unparsed: Dart owns its validation.
static const char kOpenLinkAction[] = "open-link";
static const char kLinkOpenPrefix[] = "discourse://open?";
static const gsize kMaximumLinkOpenLength = 8192;
static const guint kMaximumPendingLinkOpens = 16;

static gboolean is_link_open_request(const gchar* argument) {
  return g_ascii_strncasecmp(argument, kLinkOpenPrefix,
                             sizeof(kLinkOpenPrefix) - 1) == 0 &&
         strlen(argument) <= kMaximumLinkOpenLength;
}

static void flush_link_opens(MyApplication* self) {
  if (self->link_opens == nullptr || !self->link_opens_listening) {
    return;
  }
  for (guint i = 0; i < self->pending_link_opens->len; i++) {
    g_autoptr(FlValue) request = fl_value_new_string(static_cast<const gchar*>(
        g_ptr_array_index(self->pending_link_opens, i)));
    fl_method_channel_invoke_method(self->link_opens, "open", request, nullptr,
                                    nullptr, nullptr);
  }
  g_ptr_array_set_size(self->pending_link_opens, 0);
}

// Dart calls `listen` once it can take requests; one that launched the app
// has been waiting for it.
static void link_opens_method_call_cb(FlMethodChannel* channel,
                                      FlMethodCall* method_call,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (strcmp(fl_method_call_get_name(method_call), "listen") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  fl_method_call_respond_success(method_call, nullptr, nullptr);
  self->link_opens_listening = TRUE;
  flush_link_opens(self);
}

static void open_link_cb(GSimpleAction* action,
                         GVariant* parameter,
                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* request = g_variant_get_string(parameter, nullptr);
  if (is_link_open_request(request)) {
    // A request can launch the app before Dart is listening.
    g_ptr_array_add(self->pending_link_opens, g_strdup(request));
    if (self->pending_link_opens->len > kMaximumPendingLinkOpens) {
      g_ptr_array_remove_index(self->pending_link_opens, 0);
    }
  }
  g_application_activate(G_APPLICATION(self));
  flush_link_opens(self);
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // A second launch activates the instance already running; it gets that
  // instance's window rather than a second engine.
  GtkWindow* existing =
      gtk_application_get_active_window(GTK_APPLICATION(application));
  if (existing != nullptr) {
    gtk_window_present(existing);
    return;
  }
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
    gtk_header_bar_set_title(header_bar, "Discourse");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Discourse");
  }

  // X11 only; on Wayland the compositor owns placement and this does nothing.
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  // Geometry mirrors MainFlutterWindow.swift, so the shell opens the same size
  // on both desktops: room for rail, sidebar and content side by side.
  gtk_window_set_default_size(window, 1280, 860);

  // Below this the compact breakpoint stops fitting. Passing nullptr as the
  // geometry widget applies the hint to the whole window, header bar included,
  // so this is the outer size rather than macOS's content box -- a difference
  // small enough not to need its own layout tuning.
  GdkGeometry geometry;
  geometry.min_width = 380;
  geometry.min_height = 480;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->link_opens = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "org.discourse.native/link_opens", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->link_opens, link_opens_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // On a second launch both calls are forwarded to the instance already
  // running, which is why the request travels as an action parameter: unlike
  // a GFile, a string arrives exactly as it was given.
  const gchar* request = nullptr;
  for (gchar** argument = self->dart_entrypoint_arguments;
       *argument != nullptr; argument++) {
    if (is_link_open_request(*argument)) {
      request = *argument;
    }
  }
  if (request != nullptr) {
    g_action_group_activate_action(G_ACTION_GROUP(application),
                                   kOpenLinkAction,
                                   g_variant_new_string(request));
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);

  g_autoptr(GSimpleAction) open_link =
      g_simple_action_new(kOpenLinkAction, G_VARIANT_TYPE_STRING);
  g_signal_connect(open_link, "activate", G_CALLBACK(open_link_cb), self);
  g_action_map_add_action(G_ACTION_MAP(application), G_ACTION(open_link));
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->link_opens);
  g_clear_pointer(&self->pending_link_opens, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_link_opens = g_ptr_array_new_with_free_func(g_free);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0),
                                     nullptr));
}
