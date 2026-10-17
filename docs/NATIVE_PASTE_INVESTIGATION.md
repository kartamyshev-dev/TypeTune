# Повторная диагностика вставки Chrome, 2026-10-15

Это незавершённое расследование. Ни повторный PASS, ни исходники Chromium не
заменяют приёмку всего F07. Реальный composer Codex не проверялся.

Диагностический GUI `5d6a353b87583b8a4f66dab5fbddbeecaff2a4dfb85c2e95e9767544b06044bc`:
[identity](../research/evidence/paste-stage-build-identity.json).
Использовалась только собственная страница LP-CODEX-001 в Chrome155.0.8059.40,
синтетический LF/TAB payload, сохранение всех representations clipboard в RAM.
Личные данные и поле переписки не использовались. Во всех завершённых paste
опытах ниже modifier state нейтрален, original clipboard восстановлен.

## Наблюдения

- Первый rich опыт PASS. В следующих8 повторах6 PASS/2 FAIL; при FAIL остаётся
  исходное выделение, текст не теряется. `paste-stage-rich*.json`.
- Trace обоих FAIL: все guard/postAccess проходят; полный native frame отправлен
  за14/31мс. ACK150мс видит неизменное поле, current=true. Softdeadline200мс
  не сработал. Поэтому отказ доступа и общий deadline не объясняют эти случаи.
  [trace](../research/evidence/paste-stage-trace.json).
- Отказ повторён на пустом rich: правильный trusted KeyV/meta+alt+shift,
  paste с собственным payload, activeElement остаётся rich. События paste и
  beforeinput не отменены. В неудачном опыте нового textInput/input нет;
  beforeinput dataTransfer не совпадает с expected. Это ещё не доказывает
  clipboard sequence race: возможен другой тип beforeinput payload.
- Удержание synthetic clipboard3сек вместо800мс и pre-key settle750мс
  не устранили отказ. Product timeouts/guards не менялись.
- Отложенный UI-журнал fixture дал12/12, но немедленный контроль дал10/11;
  далее минимальная fixture без paste/beforeinput listeners тоже дала2/3.
  Следовательно, обновление журнала не установлено как единственная причина.
- Независимая native CmdAltShiftV и обычная CmdV также дали пропуск;
  после полного завершения LayoutPilot CmdAltShiftV повторно дал FAIL.
  Это ограничивает атрибуцию: для такого пропуска код LayoutPilot не обязателен.
  `paste-delivery-{native,cmdv,no-switcher}-control-rich.json`,
  `paste-minimal-no-switcher-rich.json`.

Все неудачные попытки сохранены, не заменены успешными. Никакого автоматического
повторения неудачной вставки в продукте нет: это могло бы дублировать текст.
Базовый helper останавливает блок на первом отказе.

## Дальнейшее различение

[CHROMIUM_NATIVE_PASTE_PATH](CHROMIUM_NATIVE_PASTE_PATH.md) сопоставляет именно
официальный tag установленной версии. В macOS implementation есть возможное
повторное изменение внутреннего token от отложенного callback при стабильном
NSPasteboard count. Наблюдение этого callback в установленном процессе отсутствует;
это гипотеза, не восстановленная runtime-причина.

Новый диагностический `--repeat 1…20` готовит clipboard один раз для всего блока,
с проверками владения/контекста перед каждым событием и единственным восстановлением.
Это отдельный опыт по различению setup/clipboard race; не изменение продукта.
Последний тестовый стенд не читает clipboardData и откладывает DOM-журнал.

## Новый bundle6a93cdc9: один write на блок

`short-caps-single-clipboard-plain.json`: первый блок остановлен на первом
пропуске, поле осталось пустым. Отдельно block2 plain20/20 и rich20/20 прошли,
clipboard всех типов восстановлен, modifier state нейтрален; после них Space
сохранил payload в обоих полях. Это не доказательство устранения первичного
отказа. `short-caps-limited-verification.json` явно оставляет fullAcceptance=false.

После удаления временного trace-key и restart на том же bundle Chrome word6/6
(correct/wrong/20words × plain/rich) прошли; это проверка непотери слов после
пробела на собственной странице, не проверка настоящего composer Codex.
Данные собственных clipboard listener и синхронные варианты fixture сохранены
как исторические диагностические стенды; финальный стенд не читает clipboardData.

## Диагностические контроли source/profile, 2026-10-15

Source HID не устранил пропуск независимой CmdAltShiftV без переключателей:
`paste-hid-independent-rich.json`, первый опыт FAIL, neutral/clipboard restore PASS.
В rich обычного окна отдельные plain-only и plain+RTF+HTML также дали FAIL:
`paste-profile-native-rich.json`. Добавленный helper-флаг меняет только собственный
синтетический clipboard; все guard/snapshot/ownership checks сохранены.

Затем новое incognito-окно той же локальной страницы: native block4/4 и четыре
fresh-write profile-опыта plain/multi/multi/plain прошли. В исходном обычном окне
та же fresh-write последовательность позже тоже прошла4/4, при остановленных
обоих switchers. Evidence: `paste-incognito-native-rich.json`,
`paste-incognito-fresh-profiles.json`, `paste-normal-fresh-profiles.json`.
Поэтому ни инкогнито, ни состав типов, ни HID не установлены как причина/решение.
Отсутствие extension buttons в incognito не доказывает отсутствие всех extensions.
Каждый опыт сохранил полный clipboard и нейтральность модификаторов.
Повторные PASS не отменяют ранние FAIL и не считаются исправлением F07.

Отдельно новая промежуточная GUI до punctfix прошла wrong/correct слова в Chrome,
но в stream20 одно слово осталось `ghbdtn` при сохранённой общей длине/каретке:
`f17-selection-chrome-plain.json`. Потери текста в этом опыте нет; причина пропуска
не установлена. Это FAIL функционального stream, не PASS новой GUI целиком.
