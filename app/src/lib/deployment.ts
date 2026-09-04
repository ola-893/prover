export const cc3Deployment = {
  network: 'Creditcoin CC3 Testnet',
  chainId: 102031,
  explorer: 'https://creditcoin-testnet.blockscout.com',
  promiseContracts: [
    {
      label: 'Promise Court',
      address: '0x41A8A301aef8e19FE604Cc6D24E65a37804CCDcd',
    },
    {
      label: 'Promise Book',
      address: '0x15CC59C6c3781E4F6586A6458CDfa7006f1f4Cee',
    },
    {
      label: 'Source Registry',
      address: '0xC3Ed456882C7d5FA1103f8593AdCcd6afCc2B72b',
    },
  ],
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
    {
      label: 'Bureau Evidence SBT',
      address: '0x59e4aba6868f475D572E0c491d92223F4141D442',
    },
  ],
} as const;

export const sepoliaDeployment = {
  network: 'Ethereum Sepolia',
  chainId: 11155111,
  attestcoinChainKey: 1,
  explorer: 'https://sepolia.etherscan.io',
  contracts: [
    {
      label: 'Demo Promise Source',
      address: '0x035aA06263f4Ff06fF734f5556620473ac6982fc',
    },
  ],
} as const;

export function cc3AddressUrl(address: string) {
  return `${cc3Deployment.explorer}/address/${address}`;
}

export function sepoliaAddressUrl(address: string) {
  return `${sepoliaDeployment.explorer}/address/${address}`;
}

export function shortAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}
