var AFavelaCrowdFunding = artifacts.require('AFavelaCrowdFunding')
var CFavelaCrowdFunding = artifacts.require('CFavelaCrowdFunding')

module.exports = function(deployer) {
    //deployer.deploy(AFavelaCrowdFunding)
    deployer.deploy(CFavelaCrowdFunding)
}