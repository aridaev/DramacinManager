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
    tag.span label, class: [ "badge", css ]
  end

  def provider_adapter_badge(provider)
    if provider.supported?
      tag.span t("admin.providers.adapter_ready"), class: "badge badge-success"
    else
      tag.span t("admin.providers.adapter_missing"), class: "badge badge-muted", title: t("admin.providers.adapter_missing_hint")
    end
  end

  ICONS = {
    "home"        => '<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
    "grid"        => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    "layers"      => '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5"/><path d="m3 16 9 5 9-5"/>',
    "plug"        => '<path d="M9 2v6M15 2v6"/><path d="M6 8h12v3a6 6 0 0 1-12 0V8Z"/><path d="M12 17v5"/>',
    "user"        => '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    "external"    => '<path d="M14 4h6v6"/><path d="M20 4 10 14"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>',
    "compact"     => '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "comfortable" => '<path d="M4 6h16M4 12h16M4 18h16"/><path d="M4 9h8M4 15h8" opacity=".35"/>',
    "menu"        => '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "plus"        => '<path d="M12 5v14M5 12h14"/>',
    "key"         => '<circle cx="8" cy="14" r="4"/><path d="m11 11 9-9M16 6l2 2M13 9l2 2"/>',
    "check"       => '<path d="m5 12 5 5L20 7"/>',
    "box"         => '<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="M4 7.5 12 12l8-4.5M12 12v9"/>',
    "clock"       => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    "moon" => '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/>',
    "sun" => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    "palette" => '<circle cx="12" cy="12" r="9"/><circle cx="8.5" cy="10" r="1.2"/><circle cx="12" cy="7.5" r="1.2"/><circle cx="15.5" cy="10" r="1.2"/><path d="M12 21a3 3 0 0 0 0-6h-1a2 2 0 0 1 0-4"/>'
  }.freeze

  # Ikon SVG inline (stroke) untuk shell admin.
  def dm_icon(name, size: 18)
    body = ICONS.fetch(name.to_s) { ICONS["grid"] }
    tag.svg(body.html_safe, class: "ico", width: size, height: size, viewBox: "0 0 24 24", fill: "none",
            stroke: "currentColor", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
  end

  def auth_mode_label(mode)
    t("admin.api_sources.auth_modes.#{mode.presence || 'inherit'}", default: mode.to_s)
  end
end
