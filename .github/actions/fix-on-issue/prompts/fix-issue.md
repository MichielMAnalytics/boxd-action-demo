You are fixing a GitHub issue in a cloned copy of the repo at main.

# The issue

Title: {{ISSUE_TITLE}}

Number: #{{ISSUE_NUMBER}}

Body:
```
{{ISSUE_BODY}}
```

# Your job

1. Read the codebase and understand the issue.
2. Make the minimal change required to fix it.
3. Add or update at least one test that would have caught the bug. If the project has no test suite, add one (pick a test runner idiomatic to the language).
4. Run the full test suite. Do not finish until it passes. If you cannot make it pass, stop and explain why in a final message.
5. Commit your changes on the current branch with a descriptive message. Use `git add -A && git commit -m "..."`. Use the subject line `fix: <short description> (closes #{{ISSUE_NUMBER}})`.
6. Do NOT open a PR. Do NOT push. The caller will handle that.

# Constraints

- Do not modify unrelated files.
- Keep the commit focused — one logical change per commit is ideal; multiple commits are fine.
- If the issue is ambiguous or you cannot make progress, commit whatever partial work makes sense (with a clear message) and explain blockers. Better partial than nothing.
- You are running as root in an ephemeral VM. `sudo` is not needed.

When you're done (tests pass + changes committed), print a final line: `DONE`.
