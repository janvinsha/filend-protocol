// require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");

require("dotenv").config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;

// Replace this private key with your Goerli account private key
// To export your private key from Metamask, open Metamask and
// go to Account Details > Export Private Key
// Beware: NEVER put real Ether into testing accounts
const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.13",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.8.9",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.8.4",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.8.2",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.6.6",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.6.2",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },

      {
        version: "0.6.0",

        settings: {
          optimizer: {
            enabled: true,

            runs: 200,
          },
        },
      },
    ],
  },

  networks: {
    mumbai: {
      url: "https://polygon-mumbai.g.alchemy.com/v2/Pvb6j4jNWhPVS7wWM7tGnsU0F_ntNCur",
      accounts: [PRIVATE_KEY],
    },
    hyperspace: {
      chainId: 3141,
      url: "https://api.hyperspace.node.glif.io/rpc/v1",
      accounts: [PRIVATE_KEY],
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      accounts: [PRIVATE_KEY],
    },
  },
  gasReporter: {
    enabled: true,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  // Rest of the config
  // etherscan: {
  //   // Your API key for Etherscan
  //   // Obtain one at https://etherscan.io/
  //   apiKey: process.env.ETHERSCAN_KEY,
  // },
};
