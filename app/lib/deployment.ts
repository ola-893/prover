export const cc3Deployment = {
  network: 'Creditcoin CC3 Testnet',
  chainId: 102031,
  explorer: 'https://creditcoin-testnet.blockscout.com',
  contracts: [
    {
      label: 'Ordering Court',
      address: '0xc01f7E27D4D712241B1cAAD972E0FC589146c5Ff',
    },
    {
      label: 'Covenant Book',
      address: '0x66aF3e9Ad07A236b29de7ad07083C037a4244223',
    },
    {
      label: 'Performance Bureau',
      address: '0x8Ef418F6E740950cAd8C4fa22A4F7B7990B00D74',
    },
    {
      label: 'Aave Adapter',
      address: '0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4',
    },
  ],
} as const;

export function cc3AddressUrl(address: string) {
  return `${cc3Deployment.explorer}/address/${address}`;
}

export function shortAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}
