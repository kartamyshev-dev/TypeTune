//! Explicit US/Russian letter-key conversion for a cooperating range editor.
use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    UsToRu,
    RuToUs,
}
const US: &str = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>";
const RU: &str = "ёйцукенгшщзхъфывапролджэячсмитьбюЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ";

/// An explicit command, not an automatic detector. No dictionary or system
/// layout inference. Only complete whitespace-delimited tokens are accepted.
pub fn prepare_manual(
    snapshot: Snapshot,
    direction: Direction,
    now: Instant,
    ttl: Duration,
) -> Result<Plan, Rejection> {
    snapshot.check()?;
    let caret_byte = byte_offset(&snapshot.text, snapshot.caret).ok_or(Rejection::InvalidRange)?;
    if !snapshot.text[..caret_byte].ends_with(' ')
        && snapshot.text[caret_byte..]
            .chars()
            .next()
            .is_some_and(|c| !c.is_whitespace())
    {
        return Err(Rejection::InvalidRange);
    }
    let prefix = &snapshot.text[..caret_byte];
    let (start_byte, replacement) = convert_suffix(prefix, direction)?;
    let range = prefix[..start_byte].chars().count()..snapshot.caret;
    let after_text = replace_chars(&snapshot.text, range.clone(), &replacement)?;
    let after_caret = range.start + replacement.chars().count();
    Ok(Plan {
        before: snapshot,
        range,
        replacement,
        after_text,
        after_caret,
        created: now,
        ttl,
    })
}

/// Map one complete token through the layout tables; case is preserved.
pub(crate) fn map_token(word: &str, direction: Direction) -> Result<String, Rejection> {
    if word.is_empty() {
        return Err(Rejection::InvalidRange);
    }
    let (from, to) = match direction {
        Direction::UsToRu => (US, RU),
        Direction::RuToUs => (RU, US),
    };
    let mut out = String::with_capacity(word.len());
    for c in word.chars() {
        let mapped = from
            .chars()
            .zip(to.chars())
            .find_map(|(a, b)| (a == c).then_some(b))
            .ok_or(Rejection::Unsupported)?;
        out.push(mapped);
    }
    Ok(out)
}

/// Pure conversion, including for explicitly unverified keyboard history.
pub(crate) fn convert_suffix(
    prefix: &str,
    direction: Direction,
) -> Result<(usize, String), Rejection> {
    let word_end = prefix.trim_end_matches(' ');
    let start_byte = word_end
        .rfind(char::is_whitespace)
        .map_or(0, |i| i + word_end[i..].chars().next().unwrap().len_utf8());
    let word = &word_end[start_byte..];
    let mut replacement = map_token(word, direction)?;
    replacement.push_str(&prefix[word_end.len()..]);
    if replacement.len() > MAX_REPLACEMENT_BYTES {
        return Err(Rejection::Limit);
    }
    Ok((start_byte, replacement))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn mapping_is_bijective_and_covers_all_russian_letters_in_both_cases() {
        assert_eq!(US.chars().count(), 66);
        assert_eq!(RU.chars().count(), 66);
        assert_eq!(
            US.chars().collect::<std::collections::HashSet<_>>().len(),
            66
        );
        assert_eq!(
            RU.chars().collect::<std::collections::HashSet<_>>().len(),
            66
        );
        assert_eq!(
            US.chars().zip(RU.chars()).find(|(c, _)| *c == '~'),
            Some(('~', 'Ё'))
        );
    }
}
