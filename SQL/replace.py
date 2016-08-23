#!/usr/bin/env python3
import random

# This file is a quick and dirty search + replace for credit card numbers.

with open('Store1.sql', 'w') as new_file:
    with open('Store.sql', 'r') as old_file:
        for line in old_file:
            new_string = str(random.randint(1247284246323124, 9999999999999999))
            new_file.write(line.replace("XYZ", new_string))
