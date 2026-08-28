# Gluwa USC contracts attribution

`EvmV1Decoder.sol` is vendored from the MIT-licensed npm package
`@gluwa/usc-contracts@0.1.2` published by Gluwa Inc. The Solidity source is unchanged except for
normalizing CRLF line endings to LF and removing one whitespace-only line. Its normalized SHA-256 is:

`c8569a0f743c724a138c234a3a58a28184d620b150339ebfc4f687ae209e676e`

Source package: https://www.npmjs.com/package/@gluwa/usc-contracts/v/0.1.2

The decoder exposes `public` library functions, so contracts using it contain an external library
link. For Creditcoin CC3, the canonical deployed `EvmV1Decoder` used by this MVP is
`0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f`. Local Foundry tests deploy and link their own copy;
production builds must explicitly link the chain's canonical deployed copy.

MIT License

Copyright (c) Gluwa Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
