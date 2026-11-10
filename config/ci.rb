# Executado por bin/ci. Não altera dados de desenvolvimento.
CI.run do
  step "Autoload", "bin/rails zeitwerk:check"
  step "Testes", "bin/rails test"
end
