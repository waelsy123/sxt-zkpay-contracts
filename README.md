# Space and Time | ZKPay Smart Contracts


## **Install Solidity dependencies**
   ```bash
   ./jobs/install_dependencies.sh
   
   ```

### Build the project
forge build

### Run tests
forge test
```

## Git Hooks

This repository includes a sample pre-commit hook located in `githooks/pre-commit`.
It runs linting with `solhint`, static analysis with `slither`, tests, and
verifies that coverage is 100%.

To enable it locally, symlink it into your Git hooks directory:

```bash
ln -s ../../githooks/pre-commit .git/hooks/pre-commit
````

or configure the hook location:

```
git config core.hooksPath .githooks      
```

