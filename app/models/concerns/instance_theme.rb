# Tema warna/font instance → CSS variables untuk template publik (lihat layout template/v1).
module InstanceTheme
  extend ActiveSupport::Concern

  THEME_KEYS = %w[theme_accent theme_bg_dark theme_surface_dark theme_text_dark theme_bg_light theme_surface_light theme_text_light theme_default theme_font theme_radius].freeze
  THEME_DEFAULTS = {
    "theme_accent" => "#e10037",
    "theme_bg_dark" => "#090a0d", "theme_surface_dark" => "#141518", "theme_text_dark" => "#f6f7f9",
    "theme_bg_light" => "#f6f7fa", "theme_surface_light" => "#ffffff", "theme_text_light" => "#0f1422",
    "theme_default" => "dark", "theme_font" => "default", "theme_radius" => "normal"
  }.freeze
  THEME_PRESETS = {
    "crimson" => { name: "Crimson", accent: "#e10037", bg_dark: "#090a0d", surface_dark: "#141518", text_dark: "#f6f7f9", bg_light: "#f6f7fa", surface_light: "#ffffff", text_light: "#0f1422" },
    "ocean"   => { name: "Ocean",   accent: "#2f7bff", bg_dark: "#070b14", surface_dark: "#0f1626", text_dark: "#eef3ff", bg_light: "#f3f7ff", surface_light: "#ffffff", text_light: "#0b1430" },
    "emerald" => { name: "Emerald", accent: "#16b981", bg_dark: "#07100c", surface_dark: "#0f1a14", text_dark: "#ecfdf5", bg_light: "#f2fbf6", surface_light: "#ffffff", text_light: "#06281c" },
    "violet"  => { name: "Violet",  accent: "#8b5cf6", bg_dark: "#0b0812", surface_dark: "#16112a", text_dark: "#f3efff", bg_light: "#f7f4ff", surface_light: "#ffffff", text_light: "#1a1036" },
    "amber"   => { name: "Amber",   accent: "#f59e0b", bg_dark: "#0f0b05", surface_dark: "#1a140b", text_dark: "#fff8ec", bg_light: "#fffaf0", surface_light: "#ffffff", text_light: "#2a1c05" },
    "rose"    => { name: "Rose",    accent: "#f43f8a", bg_dark: "#120910", surface_dark: "#1f1119", text_dark: "#fff0f6", bg_light: "#fff5f9", surface_light: "#ffffff", text_light: "#30101f" },
    "mono"    => { name: "Mono",    accent: "#ffffff", bg_dark: "#000000", surface_dark: "#111111", text_dark: "#ffffff", bg_light: "#ffffff", surface_light: "#f4f4f4", text_light: "#000000" }
  }.freeze
  THEME_FONTS = {
    "default" => { name: "Plus Jakarta Sans (bawaan)", stack: nil },
    "inter"   => { name: "Inter", stack: "Inter, ui-sans-serif, system-ui, sans-serif" },
    "poppins" => { name: "Poppins", stack: "Poppins, ui-sans-serif, system-ui, sans-serif" },
    "nunito"  => { name: "Nunito", stack: "Nunito, ui-sans-serif, system-ui, sans-serif" },
    "system"  => { name: "System UI", stack: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" },
    "serif"   => { name: "Serif (Georgia)", stack: "Georgia, 'Times New Roman', serif" }
  }.freeze
  GOOGLE_FONTS = { "inter" => "Inter:wght@400;600;800", "poppins" => "Poppins:wght@400;600;800", "nunito" => "Nunito:wght@400;700;800" }.freeze
  RADII = { "sharp" => [ "2px", "4px", "6px" ], "normal" => [ "6px", "10px", "14px" ], "round" => [ "10px", "16px", "22px" ] }.freeze
  HEX = /\A#[0-9a-f]{6}\z/i

  included do
    THEME_KEYS.each do |key|
      define_method(key) { settings[key] }
      define_method("#{key}=") { |v| self.settings = settings.merge(key => v.to_s.strip.downcase.presence) }
    end
    validate :validate_theme
  end

  def theme(key) = public_send(key).presence || THEME_DEFAULTS[key]
  def theme_customized? = THEME_KEYS.any? { |k| settings[k].present? && settings[k] != THEME_DEFAULTS[k] }
  def theme_font_href
    g = GOOGLE_FONTS[theme("theme_font")]
    g && "https://fonts.googleapis.com/css2?family=#{g}&display=swap"
  end

  # CSS variables yang menimpa :root template v1 (dark & light).
  def theme_css
    acc = theme("theme_accent")
    r1, r2, r3 = RADII[theme("theme_radius")] || RADII["normal"]
    font = THEME_FONTS.dig(theme("theme_font"), :stack)
    dark  = palette(theme("theme_bg_dark"), theme("theme_surface_dark"), theme("theme_text_dark"), dark: true)
    light = palette(theme("theme_bg_light"), theme("theme_surface_light"), theme("theme_text_light"), dark: false)
    common = "--accent:#{acc};--accent-500:#{shade(acc, 0.12)};--accent-700:#{shade(acc, -0.18)};--r1:#{r1};--r2:#{r2};--r3:#{r3};"
    common += "--font:#{font};" if font
    ":root{#{common}#{dark}--accent-ink:#{shade(acc, 0.30)};--accent-tint:#{mix(acc, theme('theme_bg_dark'), 0.72)};}" \
    "html[data-theme=\"light\"]{#{light}--accent-ink:#{shade(acc, -0.12)};--accent-tint:#{mix(acc, '#ffffff', 0.85)};}"
  end

  private
  def validate_theme
    THEME_KEYS.each do |k|
      v = settings[k]
      next if v.blank?
      errors.add(k.to_sym, "harus format #rrggbb") if k.end_with?("accent", "_dark", "_light") && !v.match?(HEX)
    end
    errors.add(:theme_default, "tidak valid") if settings["theme_default"].present? && !%w[dark light].include?(settings["theme_default"])
    errors.add(:theme_font, "tidak valid") if settings["theme_font"].present? && !THEME_FONTS.key?(settings["theme_font"])
    errors.add(:theme_radius, "tidak valid") if settings["theme_radius"].present? && !RADII.key?(settings["theme_radius"])
  end

  def palette(bg, surface, text, dark:)
    d = dark ? 1 : -1
    "--s-sunken:#{shade(bg, -0.35 * d)};--s0:#{bg};--s1:#{surface};--s2:#{shade(surface, 0.06 * d)};--s3:#{shade(surface, 0.12 * d)};--s4:#{shade(surface, 0.18 * d)};" \
    "--line-subtle:#{shade(surface, 0.08 * d)};--line:#{shade(surface, 0.16 * d)};--line-strong:#{shade(surface, 0.30 * d)};" \
    "--t1:#{text};--t2:#{mix(text, bg, 0.28)};--t3:#{mix(text, bg, 0.48)};"
  end

  def rgb(hex) = hex.to_s.delete("#").scan(/../).map { |h| h.to_i(16) }
  def hex(r, g, b) = format("#%02x%02x%02x", *[ r, g, b ].map { |c| c.round.clamp(0, 255) })
  # amount > 0 → lebih terang, < 0 → lebih gelap
  def shade(h, amount)
    r, g, b = rgb(h)
    t = amount.positive? ? 255 : 0
    hex(*[ r, g, b ].map { |c| c + (t - c) * amount.abs })
  end
  def mix(h1, h2, w) # w = porsi h2
    a = rgb(h1); b = rgb(h2)
    hex(*a.zip(b).map { |x, y| x * (1 - w) + y * w })
  end
end
