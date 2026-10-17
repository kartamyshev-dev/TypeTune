#!/bin/zsh -f
# Run with zsh -d -f -i. vared is an inert editor: its contents are never evaluated.
HISTFILE=/dev/null
unset HISTSIZE SAVEHIST
source "${0:A:h:h}/Sources/LayoutPilotCore/Resources/layoutpilot.zsh"
typeset -g _lp_fixture_report=${1-}
[[ ${_lp_fixture_report:A:h} == ${0:A:h:h}/research/private/probes && ${_lp_fixture_report:t} == TerminalFixture-*.json && ! -e $_lp_fixture_report ]] || exit 2
umask 077
zmodload -F zsh/files b:zf_mv
_lp_fixture_snapshot() {
  local text=$BUFFER
  case $text in
    ''|g|gh|ghb|ghbd|ghbdt|ghbdtn|'ghbdtn '|'ghbdtn  '|h|he|hel|hell|hello|'hello '|'hello  '|привет|'привет '|'привет  ') ;;
    *) text=redacted ;;
  esac
  print -r -- "{\"pid\":$$,\"nonce\":\"$_layoutpilot_nonce\",\"host\":\"$_layoutpilot_host\",\"text\":\"$text\",\"cursor\":$CURSOR,\"active\":true}" > "$_lp_fixture_report.tmp"
  zf_mv -f "$_lp_fixture_report.tmp" "$_lp_fixture_report"
}
add-zle-hook-widget line-pre-redraw _lp_fixture_snapshot
typeset fixture_text=''
while true; do
  vared -p 'LayoutPilot — тест без выполнения команд> ' fixture_text || break
  case $fixture_text in
    'привет '|'ghbdtn '|'hello '|'привет'|'ghbdtn'|'привет привет '|'ghbdtn123 '|'ghbdtn.'|'привет. '|'echo привет ')
      print -r -- "LP-FIXTURE-RESULT:$fixture_text" ;;
    *) print -r -- 'LP-FIXTURE-RESULT:unexpected data hidden' ;;
  esac
done
