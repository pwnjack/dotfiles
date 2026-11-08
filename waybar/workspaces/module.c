/* cffi/workspaces: the Waybar entry points.
 *
 * One GtkDrawingArea draws the whole row (render.c) from four animation
 * groups (anim.c) on the widget's frame clock. Colours, the numbers font and
 * the row's outer insets come from style.css (#workspaces, .active,
 * .numbers); sizes are Geometry. Hyprland state arrives through hypr.c. */
#include <gtk/gtk.h>
#include <math.h>
#include <string.h>

#include "anim.h"
#include "hypr.h"
#include "model.h"
#include "render.h"
#include "waybar_cffi_module.h"

#define ABI __attribute__((visibility("default")))

ABI const size_t wbcffi_version = 2;

#define SHAPE_US 300000 /* the morph and 6-10 growing in/out */
#define FADE_US 200000  /* occupancy and hover colour */

typedef struct {
    GtkWidget *area;
    HyprClient *hypr;
    WsState state;
    Group shape, presence, fill, hover;
    const Geometry *geo;
    Theme theme;
    guint tick_id;
    int hover_slot;
    double pointer_x; /* last pointer x, valid while pointer_inside */
    gboolean pointer_inside;
    double scroll_acc;
    int width_request, height_request;
    gboolean connected;
    gboolean in_style_update;
} Module;

static int slot_at_layout(const Module *m, const double shape[], const double presence[],
                          const double visible[], double px);

static void targets(const Module *m, double shape[], double presence[], double fill[],
                    double hover[])
{
    for (int i = 0; i <= WS_COUNT; i++) {
        bool slot = i >= 1;
        shape[i] = slot && i == m->state.active ? 1 : 0;
        /* Hyprland's active workspace exists by definition; do not wait for the
         * coalesced snapshot to say so. */
        presence[i] = slot && (ws_visible(&m->state, i) || i == m->state.active) ? 1 : 0;
        fill[i] = slot && m->state.windows[i] > 0 ? 1 : 0;
        hover[i] = slot && i == m->hover_slot ? 1 : 0;
    }
}

static GtkBorder margins(const Module *m)
{
    GtkStyleContext *ctx = gtk_widget_get_style_context(m->area);
    GtkBorder b;
    gtk_style_context_get_margin(ctx, gtk_style_context_get_state(ctx), &b);
    return b;
}

static void layout_now(const Module *m, Layout *l)
{
    layout_compute(m->geo, m->shape.value, m->presence.value, l);
}

static void update_size(Module *m)
{
    Layout l;
    layout_now(m, &l);
    GtkBorder b = margins(m);
    /* The epsilon matters: during a switch the total is exact only up to
     * floating-point noise, and ceil(110.0000000001) would add a pixel. */
    int want = (int)ceil(b.left + l.total + b.right - 1e-6);
    /* The height is requested too: the row holds the bar at its full height
     * even when every other module on it is empty (no windows open). */
    int tall = b.top + m->geo->height + b.bottom;
    if (want != m->width_request || tall != m->height_request) {
        m->width_request = want;
        m->height_request = tall;
        gtk_widget_set_size_request(m->area, want, tall);
    }
}

static gboolean tick(GtkWidget *w, GdkFrameClock *clock, gpointer user)
{
    Module *m = user;
    int64_t now = gdk_frame_clock_get_frame_time(clock);
    bool more = group_tick(&m->shape, now);
    more = group_tick(&m->presence, now) || more;
    more = group_tick(&m->fill, now) || more;
    more = group_tick(&m->hover, now) || more;
    update_size(m);
    gtk_widget_queue_draw(w);
    if (!more) {
        m->tick_id = 0;
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

/* The layout moves under a stationary pointer, which sends no motion event, so
 * the hover slot is re-derived from the last pointer position against the
 * layout the row is going TO (shape s, presence p), never the one it is leaving. */
static void settle_hover(Module *m, const double s[], const double p[], double hover[])
{
    m->hover_slot = m->pointer_inside ? slot_at_layout(m, s, p, p, m->pointer_x) : 0;
    for (int i = 0; i <= WS_COUNT; i++)
        hover[i] = i >= 1 && i == m->hover_slot ? 1 : 0;
}

/* Move every group toward the current state. */
static void animate(Module *m)
{
    double s[WS_COUNT + 1], p[WS_COUNT + 1], f[WS_COUNT + 1], h[WS_COUNT + 1];
    targets(m, s, p, f, h);
    settle_hover(m, s, p, h);
    group_retarget(&m->shape, s);
    group_retarget(&m->presence, p);
    group_retarget(&m->fill, f);
    group_retarget(&m->hover, h);
    if (!m->tick_id && (m->shape.running || m->presence.running || m->fill.running ||
                        m->hover.running))
        m->tick_id = gtk_widget_add_tick_callback(m->area, tick, m, NULL);
}

/* Show the current state at once: startup and (re)connection. A running tick
 * callback is harmless: it finds every group at rest, redraws and removes
 * itself. */
static void jump(Module *m)
{
    double s[WS_COUNT + 1], p[WS_COUNT + 1], f[WS_COUNT + 1], h[WS_COUNT + 1];
    targets(m, s, p, f, h);
    settle_hover(m, s, p, h);
    group_init(&m->shape, SHAPE_US, CURVE_STANDARD, s);
    group_init(&m->presence, SHAPE_US, CURVE_STANDARD, p);
    group_init(&m->fill, FADE_US, CURVE_EASE_OUT, f);
    group_init(&m->hover, FADE_US, CURVE_EASE_OUT, h);
    update_size(m);
    gtk_widget_queue_draw(m->area);
}

static Rgba rgba(const GdkRGBA *c)
{
    return (Rgba){c->red, c->green, c->blue, c->alpha};
}

static void load_theme(Module *m)
{
    GtkStyleContext *ctx = gtk_widget_get_style_context(m->area);
    GtkStateFlags state = gtk_style_context_get_state(ctx);
    GdkRGBA c;
    gtk_style_context_get_color(ctx, state, &c);
    m->theme.fg = rgba(&c);
    gtk_style_context_save(ctx);
    gtk_style_context_add_class(ctx, "active");
    gtk_style_context_get_color(ctx, gtk_style_context_get_state(ctx), &c);
    gtk_style_context_restore(ctx);
    m->theme.accent = rgba(&c);
    if (m->theme.font)
        pango_font_description_free(m->theme.font);
    m->theme.font = NULL;
    gtk_style_context_get(ctx, state, GTK_STYLE_PROPERTY_FONT, &m->theme.font, NULL);
}

static void on_style_updated(GtkWidget *w, gpointer user)
{
    (void)w;
    Module *m = user;
    if (m->in_style_update)
        return;
    m->in_style_update = TRUE;
    load_theme(m);
    update_size(m);
    gtk_widget_queue_draw(m->area);
    m->in_style_update = FALSE;
}

static gboolean on_draw(GtkWidget *w, cairo_t *cr, gpointer user)
{
    Module *m = user;
    Layout l;
    layout_now(m, &l);
    Amounts a = {m->shape.value, m->presence.value, m->fill.value, m->hover.value};
    render_row(cr, &m->theme, m->geo, &l, &a, margins(m).left, gtk_widget_get_allocated_height(w));
    return FALSE;
}

/* The slot under x in the layout of the given shape and presence, counting
 * only slots whose `visible` amount is at least half: each visible slot owns
 * half the gap on either side; the first also owns everything to its left and
 * the last everything to its right, like the old whole-height click targets.
 * Layout and visibility are separate so clicks can use the drawn layout with
 * the target visibility, and hover the target layout throughout. */
static int slot_at_layout(const Module *m, const double shape[], const double presence[],
                          const double visible[], double px)
{
    Layout l;
    layout_compute(m->geo, shape, presence, &l);
    double x = px - margins(m).left, half = m->geo->gap / 2.0;
    int last = 0;
    for (int i = 1; i <= WS_COUNT; i++) {
        if (visible[i] < 0.5)
            continue;
        last = i;
        if (x < l.x[i] + l.w[i] + half)
            return i;
    }
    return last;
}

/* The slot under x in the layout as drawn (clicks and motion). */
static int slot_at(const Module *m, double px)
{
    return slot_at_layout(m, m->shape.value, m->presence.value, m->presence.to, px);
}

/* Focus a workspace slot through the Lua dispatcher; the one place that
 * spells the expression. */
static void focus_slot(Module *m, int slot)
{
    char lua[64];
    g_snprintf(lua, sizeof lua, "hl.dsp.focus({ workspace = %d })", slot);
    hypr_dispatch(m->hypr, lua);
}

static gboolean on_press(GtkWidget *w, GdkEventButton *ev, gpointer user)
{
    (void)w;
    Module *m = user;
    if (ev->type != GDK_BUTTON_PRESS || ev->button != GDK_BUTTON_PRIMARY)
        return FALSE;
    int slot = slot_at(m, ev->x);
    if (!slot)
        return FALSE;
    focus_slot(m, slot);
    return TRUE;
}

static gboolean on_scroll(GtkWidget *w, GdkEventScroll *ev, gpointer user)
{
    (void)w;
    Module *m = user;
    if (gdk_event_get_pointer_emulated((GdkEvent *)ev))
        return TRUE; /* the wheel notch also arrives as SMOOTH; count it once */
    int dir = 0;
    switch (ev->direction) {
    case GDK_SCROLL_UP:
        dir = -1;
        break;
    case GDK_SCROLL_DOWN:
        dir = 1;
        break;
    case GDK_SCROLL_SMOOTH:
        m->scroll_acc += ev->delta_y;
        if (m->scroll_acc <= -1)
            dir = -1;
        else if (m->scroll_acc >= 1)
            dir = 1;
        if (dir)
            m->scroll_acc = 0;
        break;
    default:
        return FALSE;
    }
    /* Step through the slots the row draws, never past them: Hyprland's
     * relative "r+1" counts on through 11, 12, ... where no slot exists. */
    int slot = ws_step(&m->state, dir);
    if (slot)
        focus_slot(m, slot);
    return TRUE;
}

static gboolean on_motion(GtkWidget *w, GdkEventMotion *ev, gpointer user)
{
    (void)w;
    Module *m = user;
    m->pointer_x = ev->x;
    m->pointer_inside = TRUE;
    int slot = slot_at(m, ev->x);
    if (slot != m->hover_slot) {
        m->hover_slot = slot;
        animate(m);
    }
    return FALSE;
}

static gboolean on_leave(GtkWidget *w, GdkEventCrossing *ev, gpointer user)
{
    (void)w, (void)ev;
    Module *m = user;
    m->pointer_inside = FALSE;
    if (m->hover_slot) {
        m->hover_slot = 0;
        animate(m);
    }
    return FALSE;
}

static void on_active(int active, void *user)
{
    Module *m = user;
    m->state.active = active;
    animate(m);
}

static void on_snapshot(const WsState *s, void *user)
{
    Module *m = user;
    m->state = *s;
    if (!m->connected) {
        m->connected = TRUE;
        jump(m);
    } else {
        animate(m);
    }
}

static void on_disconnected(void *user)
{
    Module *m = user;
    if (!m->connected)
        return; /* already showing the default */
    m->connected = FALSE;
    ws_state_init(&m->state);
    jump(m);
}

/* options/bar-workspaces, read as the old script did: first line,
 * surrounding whitespace trimmed; "numbers" or anything else (dots). */
static gboolean numbers_mode(void)
{
    const char *dir = g_getenv("BAR_OPTIONS");
    char *path = dir && *dir ? g_build_filename(dir, "bar-workspaces", NULL)
                             : g_build_filename(g_get_home_dir(), ".config", "options",
                                                "bar-workspaces", NULL);
    char *text = NULL;
    gboolean numbers = FALSE;
    if (g_file_get_contents(path, &text, NULL, NULL)) {
        char *nl = strchr(text, '\n');
        if (nl)
            *nl = '\0';
        numbers = strcmp(g_strstrip(text), "numbers") == 0;
    }
    g_free(text);
    g_free(path);
    return numbers;
}

ABI void *wbcffi_init(const wbcffi_init_info *info, const wbcffi_config_entry *entries, size_t n)
{
    (void)entries, (void)n; /* module_path is for Waybar; source is informational */
    Module *m = g_new0(Module, 1);
    m->theme.numbers = numbers_mode();
    m->geo = m->theme.numbers ? &GEOMETRY_NUMBERS : &GEOMETRY_DOTS;
    m->width_request = m->height_request = -1;
    ws_state_init(&m->state);

    m->area = gtk_drawing_area_new();
    gtk_widget_set_name(m->area, "workspaces");
    if (m->theme.numbers)
        gtk_style_context_add_class(gtk_widget_get_style_context(m->area), "numbers");
    gtk_widget_add_events(m->area, GDK_BUTTON_PRESS_MASK | GDK_SCROLL_MASK |
                                       GDK_SMOOTH_SCROLL_MASK | GDK_POINTER_MOTION_MASK |
                                       GDK_LEAVE_NOTIFY_MASK);
    g_signal_connect(m->area, "draw", G_CALLBACK(on_draw), m);
    g_signal_connect(m->area, "style-updated", G_CALLBACK(on_style_updated), m);
    g_signal_connect(m->area, "button-press-event", G_CALLBACK(on_press), m);
    g_signal_connect(m->area, "scroll-event", G_CALLBACK(on_scroll), m);
    g_signal_connect(m->area, "motion-notify-event", G_CALLBACK(on_motion), m);
    g_signal_connect(m->area, "leave-notify-event", G_CALLBACK(on_leave), m);

    gtk_container_add(info->get_root_widget(info->obj), m->area);
    g_object_ref(m->area); /* outlive the container until deinit */
    gtk_widget_show(m->area);
    load_theme(m);
    jump(m);

    HyprCallbacks cb = {on_active, on_snapshot, on_disconnected, m};
    m->hypr = hypr_client_new(&cb);
    return m;
}

ABI void wbcffi_deinit(void *instance)
{
    Module *m = instance;
    hypr_client_free(m->hypr);
    if (m->tick_id)
        gtk_widget_remove_tick_callback(m->area, m->tick_id);
    g_signal_handlers_disconnect_by_data(m->area, m);
    if (m->theme.font)
        pango_font_description_free(m->theme.font);
    GtkWidget *area = m->area;
    g_free(m);
    g_object_unref(area);
}

/* Waybar calls these unconditionally (update on its dispatcher, refresh on
 * every signal it receives); they must exist even though state is pushed. */
ABI void wbcffi_update(void *instance)
{
    (void)instance;
}

ABI void wbcffi_refresh(void *instance, int signal)
{
    (void)instance, (void)signal;
}

ABI void wbcffi_doaction(void *instance, const char *name)
{
    (void)instance, (void)name;
}
