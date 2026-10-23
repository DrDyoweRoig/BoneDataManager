import 'package:uuid/uuid.dart';

import '../catalog/catalog.dart';
import 'layer.dart';

const _uuid = Uuid();

/// Spec §8 dental layer templates, with fresh ids. All are off until the user enables one.
List<Layer> dentalTemplates() {
  Layer t(String name, LayerType type, [List<String> options = const []]) =>
      Layer(id: _uuid.v4(), name: name, type: type, options: options, appliesTo: const [kTeethId]);
  return [
    t('Status', LayerType.singleChoice, [
      'In socket', 'Loose', 'Lost antemortem', 'Lost postmortem', 'Unerupted', 'Congenitally absent'
    ]),
    t('Wear', LayerType.singleChoice, [for (var i = 1; i <= 8; i++) '$i']),
    t('Caries', LayerType.multiChoice, ['Occlusal', 'Interproximal', 'Buccal', 'Lingual', 'Root', 'None']),
    t('Calculus', LayerType.singleChoice, ['0', '1', '2', '3']),
    t('Enamel hypoplasia', LayerType.yesNo),
    t('Periapical lesion', LayerType.yesNo),
    t('Development stage', LayerType.singleChoice, [
      'Ci', 'Cco', 'Coc', 'Cr½', 'Cr¾', 'Crc', 'Ri', 'Rcl', 'R¼', 'R½', 'R¾', 'Rc', 'A½', 'Ac'
    ]),
    t('Notes', LayerType.shortText),
  ];
}
