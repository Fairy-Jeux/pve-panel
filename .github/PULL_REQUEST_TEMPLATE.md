## Summary

<!-- Describe what this PR changes and why. -->

## Type of Change

- [ ] Bug fix (`fix:`)
- [ ] New feature (`feat:`)
- [ ] Refactoring / maintenance (`chore:` / `refactor:`)
- [ ] Documentation (`docs:`)
- [ ] CI / build (`ci:` / `build:`)
- [ ] Security fix (`security:`)

## Related Issues

<!-- Link related issues, e.g., Closes #123 -->

## Verification Performed

- [ ] Backend unit & API tests pass (`pytest` / `pytest backend/tests`)
- [ ] Backend syntax & import checks pass (`python -m compileall -q backend/app`)
- [ ] Frontend TypeScript check & production build pass (`cd frontend && npm run build`)
- [ ] Installer script syntax checked if modified (`bash -n install.sh`)
- [ ] Docker image builds cleanly (`docker build -t pve-panel:test .`)

## Security & Hygiene Checklist

- [ ] No real `.env`, `config.yaml`, `services.yaml`, `*.db`, `*.p8`, API tokens, or personal hostnames/emails are included
- [ ] Bilingual docs (`README.md` / `README.fr.md` / `docs/en/` / `docs/fr/`) updated if APIs or config options changed
