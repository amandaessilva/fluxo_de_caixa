namespace :account do
  desc 'Cria ou atualiza a única conta pessoal (e-mail e senha solicitados no terminal)'
  task setup: :environment do
    require 'io/console'
    print 'E-mail: '
    email = STDIN.gets.to_s.strip
    print 'Senha (mínimo 12 caracteres): '
    password = STDIN.noecho(&:gets).to_s.chomp
    puts
    print 'Confirme a senha: '
    confirmation = STDIN.noecho(&:gets).to_s.chomp
    puts
    abort 'As senhas não conferem.' unless password == confirmation
    user = User.first || User.new
    user.update!(email: email, password: password, password_confirmation: confirmation)
    puts 'Conta configurada. Entre pela página /acesso/new.'
  end
end
namespace :previews do
  desc 'Apaga prévias expiradas (agendar a cada 30 minutos em produção)'
  task cleanup: :environment do
    Preview.purge_expired!
  end
end
