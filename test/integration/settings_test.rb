require 'test_helper'
class SettingsTest < ActionDispatch::IntegrationTest
  setup { setup_finances; sign_in }
  test 'categoria salva limites diferentes e desfaz alteração inválida' do
    post categories_path, params: { category: { name: 'Casa' }, limits: { '1' => '100,00', '2' => '120,00' } }
    assert_redirected_to categories_path
    category = Category.find_by!(name: 'Casa')
    assert_equal [BigDecimal('100'), BigDecimal('120')], category.monthly_limits.order(:month).pluck(:amount)
    patch category_path(category), params: { category: { name: 'Mudada' }, limits: { '1' => '50', '2' => '-1' } }
    assert_response :unprocessable_entity
    assert_equal 'Casa', category.reload.name
    assert_equal BigDecimal('100'), category.monthly_limits.find_by!(month: 1).amount
  end
  test 'cria ano e conta fixa pela interface' do
    post recurring_rules_path, params: { recurring_rule: { category_id: @category.id, description: 'Internet', amount: '90,00', day: 10, starts_on: '2026-11-01', kind: 'expense' } }
    assert_redirected_to settings_path
    assert_equal 2, Entry.count
    post financial_years_path, params: { year: 2027 }
    assert_redirected_to root_path(year: 2027)
    assert_equal 12, FinancialYear.find_by!(year: 2027).entries.count
  end
  test 'restauração confirmada remove alterações posteriores ao arquivo' do
    entry
    file = Tempfile.new(['backup', '.json']); file.write(BackupService.export.to_json); file.flush
    entry(description: 'Remover')
    post backup_path, params: { file: Rack::Test::UploadedFile.new(file.path, 'application/json') }
    assert_response :success
    post restore_backup_path, params: { confirm: '1' }
    assert_redirected_to settings_path
    assert_equal 1, Entry.count
    assert_equal 1, User.count
    assert_equal 0, Preview.count
  ensure
    file&.close!
  end
  test 'prévia não pertence a outra conta e prévia expirada não confirma' do
    other = User.create!(email: 'outra@example.com', password: 'senha-sintetica-segura')
    current = other.previews.create!(purpose: 'xlsx', payload: { 'secret' => 'teste' }, expires_at: 30.minutes.from_now)
    get import_path, params: { id: current.id }
    assert_response :not_found
  end
  test 'sessão expirada exige login e senha incorreta não autentica' do
    travel 13.hours do
      get root_path
      assert_redirected_to new_session_path
    end
    delete session_path
    post session_path, params: { email: @user.email, password: 'errada' }
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to new_session_path
  end
end
