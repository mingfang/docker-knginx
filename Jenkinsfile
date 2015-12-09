node {
   stage 'Checkout'
   checkout scm
   
   stage 'Pull Ubuntu'
   docker pull ubuntu:14.04

   stage 'Build'
   sh "./build" 

   stage 'Push'
   sh "bash -x ./push"   
}
