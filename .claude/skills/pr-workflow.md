# PR Workflow

When creating a PR:

1. Check for uncommitted changes (`git status`) and commit them first
2. Get line stats: `git diff --shortstat origin/main..HEAD`
3. Get changed files: `gh pr view <n> --json files` or `git diff --name-only origin/main..HEAD`
4. Write the description using `docs/conventions/pr-template.md`
5. Create with: `gh pr create --title "..." --body "..."`

When updating an existing PR description:
- Use `gh pr edit <n> --body "..."`
- Always reflect the latest state of all commits, not just the most recent one
