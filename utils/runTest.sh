#!/bin/bash

python3 utils/update_sig_checks.py 1
npm run test
python3 utils/update_sig_checks.py 0