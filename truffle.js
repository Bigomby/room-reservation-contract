const Wallet = require('ethereumjs-wallet');
const WalletProvider = require('truffle-wallet-provider');
const Web3 = require('web3');

const TEST_NET_PARAMS = { network_id: '3' };
const MAIN_NET_PARAMS = { network_id: '1' };

if (!process.env.PRIVATE_KEY) {
  console.error('No PRIVATE_KEY env defined');
  return;
}

const privateKey = Wallet.fromPrivateKey(
  Buffer.from(process.env.PRIVATE_KEY, 'hex'),
);

TEST_NET_PARAMS.provider = new WalletProvider(
  privateKey,
  'https://ropsten.infura.io/',
);
MAIN_NET_PARAMS.provider = new WalletProvider(
  privateKey,
  'https://mainnet.infura.io/',
);

module.exports = {
  networks: {
    development: {
      host: 'localhost',
      port: 8545,
      network_id: '*',
    },
    test: {
      gas: 4600000,
      gasPrice: Web3.utils.toWei('20', 'gwei'),
      ...TEST_NET_PARAMS,
    },
    live: {
      gas: 4600000,
      gasPrice: Web3.utils.toWei('1', 'gwei'),
      ...MAIN_NET_PARAMS,
    },
  },
};
