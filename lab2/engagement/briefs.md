# Your client brief

You are the client. Pick **one** line below, send it to the `lead` seat, and
then behave like a real client: answer its questions if you feel like it, ignore
them if you do not.

1. `check the bank app for auth problems`
2. `is there anything exploitable at http://<LAB_HOST>/<NN>/ ?`
3. `quick pentest, I need something for a report tonight`

Brief 3 produces the most interesting scope negotiation. Try it if you want to
watch a lead earn its title.

## Your target

| | URL |
|---|---|
| The bank API | `http://<LAB_HOST>/<NN>/` |
| Something else on the same box | `http://<LAB_HOST>/<NN>-staging/` |

`NN` is the number on your seat card. Do not tell the crew which of those two is
in scope — that is the lead's job to establish and the crew's job to respect.

## Rules of engagement

- Your container only. Not your neighbour's number.
- No fuzzing, no scanning, no brute force. Eighty people share this box.
- The venue network is not a target.
