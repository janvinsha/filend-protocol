const main = async () => {
  const fetherFactory = await hre.ethers.getContractFactory("FEther");
  const fether = await fetherFactory.deploy(
    //filtrollerAddress
    "0xddE41e7aF3E6b3Ef46A70025d0d859166270AC49",
    //interestRateModel_
    "0x3435bB7C5EF81E606acf3fb221be1619cFe5080A",
    //initialExchangeRateMantissa_
    "200000000000000000000000000",
    //name_
    "Filend Ether",
    //symbol_
    "fETH",
    //decinmals
    8,
    //admin_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
  );
  await fether.deployed();
  console.log("fether Contract deployed to:", fether.address);
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
