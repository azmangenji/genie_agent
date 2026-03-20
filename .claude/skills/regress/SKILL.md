# Regression Skill

Run regression test suites and analyze results.

## Trigger
`/regress`

## Workflow

1. **Gather Information**
   - Regression suite (sanity, nightly, full)
   - Number of seeds per test
   - Coverage options

2. **Execute Regression**
   - Submit jobs
   - Track progress
   - Collect results

3. **Report Results**
   - Pass/fail summary
   - Coverage summary

## Regression Types

### Sanity
Quick validation, core tests, pre-commit

### Nightly
Comprehensive, multiple seeds, full coverage

### Full
All tests, maximum seeds, sign-off quality

## Result Collection
```bash
# Count results
grep -l "TEST PASSED" logs/*/sim.log | wc -l
grep -l "TEST FAILED" logs/*/sim.log | wc -l

# Merge coverage
urg -dir coverage/*/*.vdb -dbname merged.vdb
```
