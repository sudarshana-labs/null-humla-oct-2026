---
name: dom-sink-audit
description: Use when reviewing front-end source for DOM-based XSS. Enumerates every DOM write in line order, asks three fixed questions about each, and applies mechanical verdict rules, so findings do not depend on where the reviewer started reading.
---

# DOM sink audit

Do not hunt. Enumerate, then decide by rule.

## Step 1 — list every DOM write, in line order

Only these count. Include the ones that look harmless.

    .innerHTML   .outerHTML   .insertAdjacentHTML()   document.write()   .textContent   .innerText

## Step 2 — three questions per write

**Q1. Does the property parse HTML?**

    innerHTML, outerHTML, insertAdjacentHTML, document.write   ->  YES
    textContent, innerText                                     ->  NO

Decided by the property name alone. Not by how dangerous the value looks. Not
by any nearby comment.

**Q2. Where does each interpolated value come from?** Follow it back through
helpers to its origin:

    URL         location.hash, location.search, location.href, document.URL,
                document.referrer, window.name
    STORAGE     localStorage, sessionStorage, document.cookie
    MESSAGE     postMessage
    SERVER      a fetch or XHR response
    LITERAL     a string in this file
    UNRESOLVED  cannot tell from the code present

**Q3. Is there a neutralising call, and can you read its body?**

    NONE      nothing between origin and write
    PRESENT   an escaper whose body IS in the code you can see
    ABSENT    an escaper whose body is NOT

A function that replaces `<` and `>` stops tag injection. Do not call a
readable escaper insufficient unless you can name a character it misses and
quote the line proving it.

## Step 3 — verdict rules, first match wins

    Q1 = NO                                           ->  SAFE
    Q2 = LITERAL                                      ->  SAFE
    Q3 = PRESENT                                      ->  SAFE
    Q3 = ABSENT                                       ->  CANNOT DETERMINE
    Q2 = UNRESOLVED                                   ->  CANNOT DETERMINE
    Q1 = YES, Q2 in (URL, STORAGE, MESSAGE), Q3 = NONE -> EXPLOITABLE

CANNOT DETERMINE is a correct answer. Guessing that an unreadable sanitiser
works, or that it fails, is the same guess.

## Step 4 — report

The table from steps 1-3: `LINE | PROPERTY | Q1 | Q2 | Q3 | VERDICT`

Then, for EXPLOITABLE rows only:

    LINE: <number>  WHAT: <one sentence: what the attacker controls, what it reaches>

Then one line:

    CANNOT DETERMINE: <lines, or NONE>

If no row is EXPLOITABLE, say so. Reporting nothing beats reporting what is
not there.
