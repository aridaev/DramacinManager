module ApplicationHelper
  def masked_secret(value)
    return t("common.not_set") if value.blank?
    value.length > 8 ? "#{value[0, 4]}••••#{value[-4, 4]}" : "••••"
  end

  def provider_status_badge(provider)
    status = provider.last_status.to_s
    css = if provider.online? then "badge-success"
    elsif status.blank? then "badge-muted"
    elsif status == "coming" then "badge-info"
    else "badge-danger"
    end
    label = status.blank? ? t("admin.providers.status_unknown") : t("admin.providers.statuses.#{status}", default: status.titleize)
    badge = tag.span label, class: [ "badge", css ]
    # Mute kesehatan runtime (gagal beruntun) ditampilkan di samping status hub.
    if provider.respond_to?(:muted?) && provider.muted?
      badge += " " + tag.span(t("admin.providers.muted_until", at: l(provider.unavailable_until, format: :short)), class: "badge badge-danger", title: provider.last_error.to_s)
    end
    badge
  end

  def provider_adapter_badge(provider)
    if provider.supported?
      tag.span t("admin.providers.adapter_ready"), class: "badge badge-success"
    else
      tag.span t("admin.providers.adapter_missing"), class: "badge badge-muted", title: t("admin.providers.adapter_missing_hint")
    end
  end

# Ikon Lucide (dimuat dari CDN di layout; <i data-lucide> diganti SVG oleh lucide.createIcons()).
# Nama lama dipetakan ke nama Lucide supaya view yang ada tidak perlu diubah.
ICON_ALIASES = {
  "home" => "house", "grid" => "layout-grid", "plug" => "plug", "user" => "user-round", "external" => "external-link",
  "key" => "key-round", "compact" => "rows-3", "comfortable" => "rows-2", "box" => "box", "clock" => "clock",
  "check" => "check", "plus" => "plus", "menu" => "menu", "layers" => "layers", "moon" => "moon", "sun" => "sun", "palette" => "palette"
}.freeze

def dm_icon(name, size: 18)
  tag.i("", "data-lucide": ICON_ALIASES.fetch(name.to_s, name.to_s), class: "ico", width: size, height: size, style: "width:#{size}px;height:#{size}px", "aria-hidden": true)
end

  def auth_mode_label(mode)
    t("admin.api_sources.auth_modes.#{mode.presence || 'inherit'}", default: mode.to_s)
  end
end
