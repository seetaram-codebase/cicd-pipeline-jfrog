// Runs on Jenkins' built-in node, labeled 'build' — controller and build
// execution are the same single EC2 instance, with a real Docker daemon.
// See infra/jenkins-ecs/agent-ec2.tf.
//
// Branch decides the destination repo: feature/* (and anything else not
// explicitly listed below) builds into docker-sandbox-local and stops
// there — validation only, no deploy. develop/master build straight into
// docker-release-local and auto-deploy to production once the Xray gate
// passes — no manual approval step.
//
// Requires a Multibranch Pipeline job (not a plain Pipeline job), so
// env.BRANCH_NAME is populated per branch.
//
// Before first run, fill in:
//   - JF_URL / DOCKER_REGISTRY  (your JFrog Cloud instance)
//   - ECS_CLUSTER / prod service name (once the app's own ECS service
//     exists — not part of this scaffold yet)
// And create Jenkins credentials:
//   - jfrog-access-token   (Secret text)

pipeline {
  agent { label 'build' }

  environment {
    JF_URL          = 'https://trialkj7tft.jfrog.io'
    DOCKER_REGISTRY = 'trialkj7tft.jfrog.io'
    APP_NAME        = 'shipit'
    SANDBOX_REPO    = 'docker-sandbox-local'
    RELEASE_REPO    = 'docker-release-local'
    BUILD_NAME      = 'shipit'
    ECS_CLUSTER     = 'jfrog-demo-app'

    GIT_SHA   = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
    IMAGE_TAG = "${GIT_SHA}-${env.BUILD_NUMBER}"
    BRANCH    = "${env.BRANCH_NAME ?: 'unknown'}"
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('JFrog CLI setup') {
      steps {
        withCredentials([string(credentialsId: 'jfrog-access-token', variable: 'JF_ACCESS_TOKEN')]) {
          sh 'jf c add jfrog-server --url=$JF_URL --access-token=$JF_ACCESS_TOKEN --interactive=false'
          sh 'jf c use jfrog-server'
        }
      }
    }

    stage('Route by branch') {
      steps {
        script {
          env.IS_RELEASE  = (env.BRANCH in ['develop', 'master']).toString()
          env.TARGET_REPO = (env.IS_RELEASE == 'true') ? env.RELEASE_REPO : env.SANDBOX_REPO
          echo "Branch '${env.BRANCH}' -> ${env.TARGET_REPO} (release=${env.IS_RELEASE})"
        }
      }
    }

    stage('Build image') {
      steps {
        script {
          env.BASE_IMAGE = sh(
            script: "grep -oP '(?<=PYTHON_VERSION=).*' app/base-image.env",
            returnStdout: true
          ).trim()
        }
        sh """
          docker build \
            --build-arg PYTHON_VERSION=${BASE_IMAGE} \
            --build-arg GIT_COMMIT=${GIT_SHA} \
            --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
            --build-arg IMAGE_TAG=${IMAGE_TAG} \
            -t ${DOCKER_REGISTRY}/${TARGET_REPO}/${APP_NAME}:${IMAGE_TAG} \
            app/
        """
      }
    }

    stage('Push + publish build-info') {
      steps {
        sh "jf docker push ${DOCKER_REGISTRY}/${TARGET_REPO}/${APP_NAME}:${IMAGE_TAG} --build-name=${BUILD_NAME} --build-number=${BUILD_NUMBER}"
        sh "jf rt build-collect-env ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-add-git ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-publish ${BUILD_NAME} ${BUILD_NUMBER}"
      }
    }

    stage('Xray scan — gate') {
      steps {
        sh "jf build-scan ${BUILD_NAME} ${BUILD_NUMBER} --fail=true"
      }
    }

    stage('Deploy to ECS production') {
      when { environment name: 'IS_RELEASE', value: 'true' }
      steps {
        sh "aws ecs update-service --cluster ${ECS_CLUSTER} --service shipit-production --force-new-deployment"
      }
    }
  }

  post {
    always {
      sh 'jf c remove jfrog-server || true'
    }
  }
}
