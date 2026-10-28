# Memetakan Host request → Instance (lewat tabel domains). Dipakai constraint rute agar domain kustom
# dilayani template instance di root path, sementara host utama tetap memakai /template/v1 dan /admin.
class InstanceHost
  ENV_KEY = "dracin.instance".freeze
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)
  TTL = 60.seconds

  def self.resolve(env)
    env.fetch(ENV_KEY) { env[ENV_KEY] = lookup(ActionDispatch::Request.new(env).host) }
  end

  def self.lookup(host)
    h = host.to_s.downcase.delete_prefix("www.")
    return nil if h.blank? || h == "localhost" || h.match?(/\A[\d.:]+\z/)
    id = STORE.fetch([ "host", h ], expires_in: TTL) { Domain.find_for_host(h)&.instance_id || 0 }
    id.zero? ? nil : Instance.find_by(id: id)
  end

  def self.forget(host) = STORE.delete([ "host", host.to_s.downcase.delete_prefix("www.") ])

  # Domain instance dengan template tertentu: constraints InstanceHost::Constraint.new("v1") { ... }
  # Instance dijeda/nonaktif tetap cocok; halaman "dijeda" dirender oleh controller template.
  class Constraint
    def initialize(template = nil) = @template = template
    def matches?(request)
      inst = InstanceHost.resolve(request.env)
      inst.present? && (@template.nil? ? Instance::TEMPLATES.key?(inst.template_key) : inst.template_key == @template)
    end
  end
end
