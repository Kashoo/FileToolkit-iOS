#!/bin/sh

#  DataDecryptor.sh
#  Kashoo
#
#  Created by Ben Kennedy on 29-10-2013.
#  Copyright (c) 2013 Kashoo Cloud Accounting Inc. All rights reserved.

# This is a stand-alone decoding tool to complement the DataEncryptor three-phase compression and encryption utility.
# See DataEncryptor.m for discussion and initial configuration notes.

set -ue # Ensure all param vars are set, and abort on any pipeline failure.

if [[ !("$#" == 4) ]]; then
    echo "usage: `basename "$0"` <privatekeyfile> <infoplistfile> <inputfile> <outputfile>";
    exit 1;
fi

PRIVATEKEYFILE="$1" # PEM-encoded private key, used for decrypting the symmetric key.
INFOPLISTFILE="$2"  # property list containing the randomly-generated, asymmetrically-encrypted base64-encoded symmetric key.
INPUTFILE="$3"      # gzip-compressed, symmetrically-encrypted principal data payload.
OUTPUTFILE="$4"     # path at which to write the final plaintext output.

for FILE in "$PRIVATEKEYFILE" "$INFOPLISTFILE" "$INPUTFILE"; do
    if [ ! -f "$FILE" ]; then
        echo "$FILE not found";
        exit 1;
    fi
done

# 1. Extract the randomly-generated asymmetrically-encrypted base64-encoded symmetric key from the accompanying plist,
# 2. Decode it to binary data,
# 3. Decrypt it with the private key,
# 4. Render it as a string of hexadecimal digits.
SYMMETRICKEY=`/usr/libexec/PlistBuddy -c 'Print encryptedKey' "$INFOPLISTFILE" \
            | base64 -D                                                        \
            | openssl rsautl -inkey "$PRIVATEKEYFILE" -decrypt                 \
            | hexdump -v -e '/1 "%02x" ""'                                     \
`;

# 5. Decrypt the gzipped payload ciphertext using the symmetric key,
# 6. Decompress the gzipped payload into its original plaintext.
openssl enc -aes256 -d -iv 0 -K "$SYMMETRICKEY" -in "$INPUTFILE" | gzip -d -c >"$OUTPUTFILE"

# End.
