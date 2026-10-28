admin = User.find_or_initialize_by(email: "kgayuli.arida@gmail.com")
admin.password = "Mandiri00123@"
admin.password_confirmation = "Mandiri00123@"
admin.role = :admin
admin.save!
puts "Admin ready: #{admin.email}"

Provider.sync_catalog!
puts "Providers ready: #{Provider.count}"
