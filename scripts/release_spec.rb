# Делает project.release.yml для сборки в App Store / TestFlight из обычного project.yml:
#  - подпись аккаунтом разработчика (APPLE_TEAM_ID), автоматические профили
#  - полные права: пуши, домены (универсальные ссылки, App Clip), App Group, HealthKit, NFC, SharePlay
#  - встраивает приложение для Apple Watch и App Clip
# Запуск: APPLE_TEAM_ID=ABCDE12345 APP_DOMAIN=fit-app.brootai.workers.dev ruby scripts/release_spec.rb
require 'yaml'

team = ENV['APPLE_TEAM_ID'].to_s.strip
abort 'Нет APPLE_TEAM_ID' if team.empty?
domain = (ENV['APP_DOMAIN'].to_s.strip.empty? ? 'fit-app.brootai.workers.dev' : ENV['APP_DOMAIN'].strip)

spec = YAML.load_file('project.yml')
spec['settings']['base']['DEVELOPMENT_TEAM'] = team
spec['settings']['base']['CODE_SIGN_STYLE'] = 'Automatic'

app = spec['targets']['Oxion']
app['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = 'Oxion/Oxion.release.entitlements'
app['dependencies'] ||= []
app['dependencies'] << { 'target' => 'OxionWatch' } unless app['dependencies'].any? { |d| d['target'] == 'OxionWatch' }
app['dependencies'] << { 'target' => 'OxionClip' } unless app['dependencies'].any? { |d| d['target'] == 'OxionClip' }
app['sources'].each { |s| (s['excludes'] << 'Oxion.release.entitlements') if s.is_a?(Hash) && s['excludes'] && !s['excludes'].include?('Oxion.release.entitlements') }

File.write('project.release.yml', spec.to_yaml)

# домен в правах приложения и App Clip
%w[Oxion/Oxion.release.entitlements OxionClip/OxionClip.entitlements].each do |f|
  File.write(f, File.read(f).gsub('fit-app.brootai.workers.dev', domain))
end
puts "project.release.yml готов: команда #{team}, домен #{domain}"
