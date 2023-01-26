const main = async () => {
  const fercFactory = await hre.ethers.getContractFactory("FErc20");
  const ferc = await fercFactory.deploy();
  await ferc.deployed();
  console.log("FERC20Contract deployed to:", ferc.address);

  const fetherFactory = await hre.ethers.getContractFactory("FEther");
  const fether = await fetherFactory.deploy();
  await fether.deployed();
  console.log("FETHERContract deployed to:", fether.address);

  const fileFactory = await hre.ethers.getContractFactory("Filetroller");
  const file = await fileFactory.deploy();
  await file.deployed();
  console.log("FiletrollerContract deployed to:", file.address);

  const ftokenFactory = await hre.ethers.getContractFactory("FToken");
  const ftoken = await ftokenFactory.deploy();
  await ftoken.deployed();
  console.log("FtokenContract deployed to:", ftoken.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
