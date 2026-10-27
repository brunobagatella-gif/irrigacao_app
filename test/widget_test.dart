// Mantido para o `flutter create .` não gerar o teste padrão (que referencia MyApp).
// Os testes do projeto estão em fuzzy_test.dart.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () => expect(1 + 1, 2));
}
