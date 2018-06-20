local kube = import "kube.libsonnet";

// aka lts-alpine
local version = "2.121.1-alpine";

local archSelector(arch) = {"beta.kubernetes.io/arch": arch};

local HashedConfigMap(name) = kube.ConfigMap(name) {
  local this = self,
  metadata+: {
    local hash = std.substr(std.md5(std.toString(this.data)), 0, 7),
    name: super.name + "-" + hash,
  },
};

{
  namespace:: {metadata+: {namespace: "gus"}},
  //ns: kube.Namespace($.namespace.metadata.namespace),

  // dummy service to capture local web proxy
  http_proxy:: kube.Service("proxy") {
    metadata+: {namespace: "webcache"},
    spec: {ports: [{port: 80}]},
  },

  // List of plugins to be install during Jenkins master start
  plugins:: {
    kubernetes: "1.4",
    prometheus: "1.1.1",
    /*
    "workflow-aggregator": "2.5",
    "workflow-job": "2.15",
    "credentials-binding": "1.13",
    git: "3.6.4",
    github: "1.29.0",
    "github-branch-source": "2.3.3",
    blueocean: "1.4.2",
    "kubernetes-cli": "1.0.0",
    */
  },

  logging:: {
    level:: "FINEST",
    handlers: "java.util.logging.ConsoleHandler",
    "jenkins.level": self.level,
    "java.util.logging.ConsoleHandler.formatter": "java.util.logging.SimpleFormatter",
    "java.util.logging.ConsoleHandler.level": self.level,
  },

  // Used to approve a list of groovy functions in pipelines used the
  // script-security plugin. Can be viewed under /scriptApproval
  scriptApproval:: [
    //"method groovy.json.JsonSlurperClassic parseText java.lang.String",
    //"new groovy.json.JsonSlurperClassic",
  ],

  config: HashedConfigMap("jenkins") + $.namespace {
    data+: {
      "config.xml":
      ("<?xml version='1.0' encoding='UTF-8'?>\n" +
       std.manifestXmlJsonml([
         "hudson",
         ["disabledAdministrativeMonitors"],
         ["version", "${JENKINS_VERSION}"],
         ["numExecutors", std.toString(0)],
         ["mode", "NORMAL"],
         ["useSecurity", std.toString(true)],
         ["authorizationStrategy",
          {class: "hudson.security.FullControlOnceLoggedInAuthorizationStrategy"},
          ["denyAnonymousReadAccess", std.toString(true)],
         ],
         ["securityRealm", {class: "hudson.security.LegacySecurityRealm"}],
         ["disableRememberMe", std.toString(false)],
         ["projectNamingStrategy", {class: "jenkins.model.ProjectNamingStrategy$DefaultProjectNamingStrategy"}],
         ["workspaceDir", "${JENKINS_HOME}/workspace/${ITEM_FULLNAME}"],
         ["buildsDir", "${ITEM_ROOTDIR}/builds"],
         ["markupFormatter", {class: "hudson.markup.EscapedMarkupFormatter"}],
         ["jdks"],
         ["viewsTabBar", {class: "hudson.views.DefaultViewsTabBar"}],
         ["myViewsTabBar", {class: "hudson.views.DefaultMyViewsTabBar"}],
         ["clouds",
          ["org.csanchez.jenkins.plugins.kubernetes.KubernetesCloud",
           {plugin: "kubernetes@" + $.plugins.kubernetes},
           ["name", "kubernetes"],
           ["templates",
            // TODO: transcribe from a regular jsonnet PodSpec declaration
            ["org.csanchez.jenkins.plugins.kubernetes.PodTemplate",
             ["inheritFrom"],
             ["name", "default"],
             ["instanceCap", std.toString(2147483647)], // INT_MAX
             ["idleMinutes", std.toString(0)],
             ["label", "jenkins-agent"],
             ["nodeSelector",
              std.join(",", [
                "%s=%s" % kv for kv in kube.objectItems(archSelector("amd64"))])],
             ["nodeUsageMode", "NORMAL"],
             ["volumes"],
             ["containers",
              ["org.csanchez.jenkins.plugins.kubernetes.ContainerTemplate",
               ["name", "jnlp"],
               ["image", "jenkins/jnlp-slave:3.16-1-alpine"],
               ["privileged", std.toString(false)],
               ["workingDir", "/home/jenkins"],
               ["command"],
               ["args", "${computer.jnlpmac} ${computer.name}"],
               ["ttyEnabled", std.toString(false)],
               ["resourceRequestCpu", "2"],
               ["resourceRequestMemory", "256Mi"],
               //["resourceLimitCpu", "2"],
               //["resourceLimitMemory", "256Mi"],
               ["envVars",
                ["org.csanchez.jenkins.plugins.kubernetes.ContainerEnvVar",
                 ["key", "JENKINS_URL"],
                 ["value", $.masterSvc.http_url],
                ],
               ],
              ],
             ],
             ["envVars"],
             ["annotations"],
             ["imagePullSecrets"],
             ["nodeProperties"],
            ],
           ],
           ["serverUrl", "https://kubernetes.default"],
           ["skipTlsVerify", std.toString(false)],
           ["namespace", $.namespace.metadata.namespace],
           ["jenkinsUrl", $.masterSvc.http_url],
           ["jenkinsTunnel", $.agentSvc.host_colon_port],
           ["containerCap", std.toString(10)],
           ["retentionTimeout", std.toString(5)],
           ["connectTimeout", std.toString(5)],
           ["readTimeout", std.toString(15)],
          ],
         ],
         ["quietPeriod", std.toString(5)],
         ["scmCheckoutRetryCount", std.toString(0)],
         ["views",
          ["hudson.model.AllView",
           ["owner", {class: "hudson", reference: "../../.."}],
           ["name", "All"],
           ["filterExecutors", std.toString(false)],
           ["filterQueue", std.toString(false)],
           ["properties", {class: "hudson.model.View$PropertyList"}],
          ],
         ],
         ["primaryView", "All"],
         ["slaveAgentPort", $.master.spec.template.spec.containers_.jenkins.ports_.agent],
         ["disabledAgentProtocols",
          ["string", "JNLP-connect"],
          ["string", "JNLP2-connect"],
         ],
         ["label"],
         ["crumbIssuer", {class: "hudson.security.csrf.DefaultCrumbIssuer"},
          ["excludeClientIPFromCrumb", std.toString(true)],
         ],
         ["nodeProperties"],
         ["globalNodeProperties",
          ["hudson.slaves.EnvironmentVariablesNodeProperty",
           ["envVars", {serialization: "custom"},
            ["unserializable-parents"],
            ["tree-map",
             ["default",
              ["comparator", {class: "hudson.util.CaseInsensitiveComparator"}],
             ],
             ["int", std.toString(2)],
             ["string", "http_proxy"],
             ["string", $.http_proxy.http_url],
             ["string", "no_proxy"],
             ["string", ".lan,.local,.cluster,.svc"],
            ],
           ],
          ],
         ],
         ["noUsageStatistics", std.toString(true)],
       ])),

      "scriptapproval.xml.override":
      ("<?xml version='1.0' encoding='UTF-8'?>\n" +
       std.manifestXmlJsonml([
         "scriptApproval",
         {plugin: "script-security@1.27"},
         ["approvedScriptHashes"],
         ["approvedSignatures"] + [["string", a] for a in $.scriptApproval],
         ["aclApprovedSignatures"],
         ["approvedClasspathEntries"],
         ["pendingScripts"],
         ["pendingSignatures"],
         ["pendingClasspathEntries"],
       ])),

      "log.properties.override": std.join("\n", [
        "%s=%s" % kv for kv in kube.objectItems($.logging)]),

      // remove the wizard "install additional plugins" banner
      "jenkins.install.UpgradeWizard.state": "2.0\n",
    },
  },

  initScripts: HashedConfigMap("jenkins-init") + $.namespace {
    data+: {
      "init.groovy": |||
        import jenkins.model.*
        Jenkins.instance.setNumExecutors(0)
      |||,
    },
  },

  // manually managed for now. TODO: sealed-secrets
  secret:: kube.Secret("jenkins") + $.namespace {
    // If data_ is changed, reseal with ./seal.sh jenkins-secret.jsonnet
    data_:: {
      "admin-user": error "secret! value not overridden",
      "admin-password": error "secret! value not overridden",
    },
    spec+: {
    },
  },

  agentSvc: kube.Service("jenkins-agent") + $.namespace {
    target_pod: $.master.spec.template,
    spec+: {
      clusterIP: "None", // headless
      ports: [
        {
          port: 50000,
          targetPort: "agent",
          name: "agent",
        },
      ],
    },
  },

  masterSvc: kube.Service("jenkins") + $.namespace {
    target_pod: $.master.spec.template,
    spec+: {
      ports: [
        {
          port: 80,
          name: "http",
          targetPort: "http",
        },
      ],
    },
  },

  /*
  masterPolicy: kube.NetworkPolicy("jenkins") + $.namespace {
    target: $.master,
    spec+: {
      local master = $.master.spec.template.spec.containers_.jenkins,
      ingress: [
        // Allow web access to UI
        {
          ports: [{port: master.ports_.http.containerPort}],
        },
        // Allow inbound connections from slave
        {
          from: [{podSelector: {matchLabels: {"jenkins": "slave"}}}],
          ports: [
            {port: master.ports_.http.containerPort},
            {port: master.ports_.agent.containerPort},
          ],
        },
      ],
    },
  },
  */

  /*
  agentPolicy: kube.NetworkPolicy("jenkins-agent") + $.namespace {
    spec+: {
      podSelector: {matchLabels: {"jenkins": "slave"}},
      // Deny all ingress
    },
  },
  */

  serviceAccount: kube.ServiceAccount("jenkins") + $.namespace,

  // for jenkins kubernetes plugin
  k8sExecutorRole: kube.Role("jenkins-executor") + $.namespace {
    rules: [
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["create", "delete", "get", "list", "patch", "update", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["pods/exec"],
        verbs: ["create", "delete", "get", "list", "patch", "update", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["pods/log"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["secrets"],  // is this really required?
        verbs: ["get"],
      },
    ],
  },

  k8sExecutorBinding: kube.RoleBinding("jenkins-executor") + $.namespace {
    roleRef_: $.k8sExecutorRole,
    subjects_: [$.serviceAccount],
  },

  ing: kube.Ingress("jenkins") + $.namespace {
    local this = self,
    metadata+: {
      labels+: {
        "stable.k8s.psg.io/kcm.class": "default",
      },
      annotations+: {
        "stable.k8s.psg.io/kcm.email": "sre@bitnami.com",
        "stable.k8s.psg.io/kcm.provider": "route53",
      },
    },
    host:: "jenkins-prod-runtime.k.dev.bitnami.net",
    target_svc:: $.masterSvc,
    spec+: {
      rules: [{
        host: this.host,
        http: {
          paths: [
            {path: "/", backend: this.target_svc.name_port},
          ],
        },
      }],
      tls: [{
        hosts: [this.host],
        secretName: this.metadata.name + "-cert",
      }],
    },
  },

  pvc: kube.PersistentVolumeClaim("jenkins-data") + $.namespace {
    storage: "10Gi",
  },

  // FIXME: should be a StatefulSet, but they don't update well :(
  master: kube.Deployment("jenkins") + $.namespace {
    spec+: {
      template+: {
        spec+: {
          nodeSelector+: archSelector("amd64"),
          terminationGracePeriodSeconds: 30,
          serviceAccountName: $.serviceAccount.metadata.name,
          securityContext+: {
            runAsUser: 1000, // "jenkins"
            fsGroup: self.runAsUser,
          },
          volumes_+: {
            home: kube.PersistentVolumeClaimVolume($.pvc),
            config: kube.ConfigMapVolume($.config),
            init: kube.ConfigMapVolume($.initScripts),
            plugins: kube.EmptyDirVolume(),
            secrets: kube.EmptyDirVolume(), // todo
          },
          initContainers_+: {
            // TODO: The "right" thing to do is to build a custom
            // image, rather than download these again on every
            // container restart..
            plugins: kube.Container("plugins") {
              image: "jenkins/jenkins:" + version,
              command: ["install-plugins.sh"],
              args: ["%s:%s" % kv for kv in kube.objectItems($.plugins)],
              env_+: {
                http_proxy: $.http_proxy.http_url,
              },
              volumeMounts_+: {
                plugins: {mountPath: "/usr/share/jenkins/ref/plugins", readOnly: false},
              },
            },
          },
          containers_+: {
            jenkins: kube.Container("jenkins") {
              local container = self,
              image: "jenkins/jenkins:" + version,
              args_+: {
              },
              env_+: {
                JAVA_OPTS: std.join(" ", [
                  //"-XX:+UnlockExperimentalVMOptions",
                  //"-XX:+UseCGroupMemoryLimitForHeap",
                  //"-XX:MaxRAMFraction=1",
                  "-Xmx%dm" % (kube.siToNum(container.resources.limits.memory) /
                               std.pow(2, 20) - 100),
                  "-XshowSettings:vm",
                  "-Dhudson.slaves.NodeProvisioner.initialDelay=0",
                  "-Dhudson.slaves.NodeProvisioner.MARGIN=50",
                  "-Dhudson.slaves.NodeProvisioner.MARGIN0=0.85",
                  //"-Djava.util.logging.config.file=/var/jenkins_home/log.properties",
                  "-Dhttp.proxyHost=%s" % $.http_proxy.host,
                  "-Dhttp.proxyPort=%s" % $.http_proxy.spec.ports[0].port,
                ]),
                JENKINS_OPTS: std.join(" ", [
                  "--argumentsRealm.passwd.$(ADMIN_USER)=$(ADMIN_PASSWORD)",
                  "--argumentsRealm.roles.$(ADMIN_USER)=admin",
                ]),
                ADMIN_USER: kube.SecretKeyRef($.secret, "admin-user"),
                ADMIN_PASSWORD: kube.SecretKeyRef($.secret, "admin-password"),
                http_proxy: $.http_proxy.http_url,
              },
              ports_+: {
                http: {containerPort: 8080},
                agent: {containerPort: 50000},
                ssh: {containerPort: 50022}, // disabled by default
              },
              readinessProbe: {
                httpGet: {path: "/login", port: "http"},
                timeoutSeconds: 5,
                periodSeconds: 30,
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 10*60,  // Java :(
              },
              resources: {
                limits: {cpu: "500m", memory: "1Gi"},
                requests: {cpu: "10m", memory: "700Mi"},
              },
              volumeMounts_+: {
                home: {mountPath: "/var/jenkins_home", readOnly: false},
                config: {mountPath: "/usr/share/jenkins/ref", readOnly: true},
                init: {mountPath: "/usr/share/jenkins/ref/init.groovy.d", readOnly: true},
                plugins: {mountPath: "/usr/share/jenkins/ref/plugins", readOnly: true},
                secrets: {mountPath: "/usr/share/jenkins/ref/secrets", readOnly: true},
              },
            },
          },
        },
      },
    },
  },
}
