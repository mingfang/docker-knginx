node {
   stage 'Checkout'
   checkout scm
   
   stage 'Build'
   sh "./build --no-cache" 

   stage 'Push'
   sh "bash -x ./push"   
}
