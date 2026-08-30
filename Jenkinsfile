// Runs on Jenkins' built-in node, labeled 'build' — controller and build
// execution are the same single EC2 instance, with a real Docker daemon.
// See infra/jenkins-ecs/agent-ec2.tf.
//
// Before first run, fill in:
//   - JF_URL / DOCKER_REGISTRY  (your JFrog Cloud instance)
//   - ECS_CLUSTER / staging & prod service names (once the app's own
//     ECS services exist — not part of this scaffold yet)
// And create Jenkins credentials:
//   - jfrog-access-token   (Secret text)

pipeline {
  agent { label 'build' }

  environment {
    JF_URL          = 'https://trialkj7tft.jfrog.io'
    DOCKER_REGISTRY = 'trialkj7tft.jfrog.io'
    APP_NAME        = 'shipit'
    DEV_REPO        = 'docker-dev-local'
    STAGING_REPO    = 'docker-staging-local'
    RELEASE_REPO    = 'docker-release-local'
    BUILD_NAME      = 'shipit'
    ECS_CLUSTER     = 'jfrog-demo-app'

    GIT_SHA   = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
    IMAGE_TAG = "${GIT_SHA}-${env.BUILD_NUMBER}"
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
            -t ${DOCKER_REGISTRY}/${DEV_REPO}/${APP_NAME}:${IMAGE_TAG} \
            app/
        """
      }
    }

    stage('Push + publish build-info') {
      steps {
        sh "jf docker push ${DOCKER_REGISTRY}/${DEV_REPO}/${APP_NAME}:${IMAGE_TAG} --build-name=${BUILD_NAME} --build-number=${BUILD_NUMBER}"
        sh "jf rt build-collect-env ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-add-git ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-publish ${BUILD_NAME} ${BUILD_NUMBER}"
      }
    }

    stage('Xray scan — Gate 1') {
      steps {
        sh "jf build-scan ${BUILD_NAME} ${BUILD_NUMBER} --fail=true"
      }
    }

    stage('Promote: dev -> staging') {
      steps {
        sh "jf rt build-promote ${BUILD_NAME} ${BUILD_NUMBER} ${STAGING_REPO} --source-repo=${DEV_REPO} --copy=true"
      }
    }

    stage('Deploy to ECS staging') {
      steps {
        sh "aws ecs update-service --cluster ${ECS_CLUSTER} --service shipit-staging --force-new-deployment"
      }
    }

    stage('Smoke test: staging') {
      steps {
        sh 'sleep 30'
        sh 'curl -sf $STAGING_URL/health'
      }
    }

    stage('Approve: staging -> release') {
      steps {
        input message: 'Promote this build to production?', ok: 'Promote'
      }
    }

    stage('Promote: staging -> release — Gate 2') {
      steps {
        sh "jf rt build-promote ${BUILD_NAME} ${BUILD_NUMBER} ${RELEASE_REPO} --source-repo=${STAGING_REPO} --copy=true"
      }
    }

    stage('Deploy to ECS production') {
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
