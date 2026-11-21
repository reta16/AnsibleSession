// Activity 4, Docker fallback: lint -> syntax check -> deploy with Ansible -> smoke test
// Same stages as solutions/activity4/Jenkinsfile, but against the local containers
// (inventory/docker.ini) and without any AWS credentials.
//
// Jenkins credentials this pipeline expects (Manage Jenkins > Credentials > System > Global):
//   ec2-ssh-key          SSH Username with private key   username 'ubuntu', key = contents of ~/.ssh/session6-docker-key
//   ansible-vault-pass   Secret text                     your Activity 3 vault password
//
// Use it either way:
//   - in the Jenkins job: Pipeline > Script Path = docker-fallback/Jenkinsfile.docker
//   - or copy it to the repo root:  cp docker-fallback/Jenkinsfile.docker Jenkinsfile
// Start the containers first: bash docker-fallback/up.sh

pipeline {
    agent any

    // Jenkins on your VM isn't reachable from GitHub, so it checks GitHub
    // for new commits every 2 minutes instead of waiting for a webhook.
    // (The trigger only starts working after the first manual "Build Now".)
    triggers {
        pollSCM('H/2 * * * *')
    }

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        INVENTORY           = 'inventory/docker.ini'
        ANSIBLE_FORCE_COLOR = 'true'
    }

    stages {
        stage('Lint') {
            steps {
                sh 'yamllint .'
                sh 'ansible-lint site.yml'
            }
        }

        stage('Syntax check') {
            steps {
                // 'localhost,' is a throwaway inventory: syntax check doesn't need real servers
                sh 'ansible-playbook -i localhost, site.yml --syntax-check'
            }
        }

        stage('Deploy') {
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER'),
                    string(credentialsId: 'ansible-vault-pass',    variable: 'ANSIBLE_VAULT_PASSWORD')
                ]) {
                    // Single quotes: the shell expands $SSH_KEY etc., not Groovy,
                    // so secrets never appear in the Groovy string.
                    // -e (not --private-key/-u): inventory/docker.ini sets the key path for
                    // vboxuser, and inventory variables beat --private-key; extra vars beat both.
                    sh '''
                        chmod +x scripts/vault-pass-from-env.sh
                        echo "Servers in the inventory:"
                        ansible-inventory -i "$INVENTORY" --graph --vault-password-file scripts/vault-pass-from-env.sh
                        ansible-playbook -i "$INVENTORY" site.yml \
                          -e ansible_ssh_private_key_file="$SSH_KEY" -e ansible_user="$SSH_USER" \
                          --vault-password-file scripts/vault-pass-from-env.sh
                    '''
                }
            }
        }

        stage('Smoke test') {
            steps {
                withCredentials([
                    string(credentialsId: 'ansible-vault-pass', variable: 'ANSIBLE_VAULT_PASSWORD')
                ]) {
                    sh '''
                        ansible-playbook -i "$INVENTORY" smoke-test.yml \
                          --vault-password-file scripts/vault-pass-from-env.sh
                    '''
                }
            }
        }
    }

    post {
        success { echo 'Deployed and verified. Open http://172.30.0.11/ and http://172.30.0.12/ on the VM.' }
        failure { echo 'Pipeline failed - read the first red error in the stage that failed.' }
    }
}
